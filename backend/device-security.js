'use strict';
const crypto = require('node:crypto');

class ApiError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const fail = (status, code) => { throw new ApiError(status, code); };
const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
function identifier(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value) || ['__proto__', 'prototype', 'constructor'].includes(value)) fail(400, 'invalid_identifier');
  return value;
}
function name(value) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > 100) fail(400, 'invalid_name');
  return value.trim();
}
function fields(body, allowed) {
  if (!body || typeof body !== 'object' || Array.isArray(body)
      || Object.keys(body).some((key) => !allowed.includes(key))) fail(400, 'invalid_fields');
}
function owner(device, uid) {
  if (!device || device.active !== true || device.owner_uid !== uid || device.members?.[uid] !== 'owner') fail(403, 'owner_required');
}
async function authenticate(auth, header) {
  const match = typeof header === 'string' && header.match(/^Bearer ([^\s]+)$/);
  if (!match) fail(401, 'authentication_required');
  let token;
  try { token = await auth.verifyIdToken(match[1], true); } catch { fail(401, 'invalid_token'); }
  if (!token.uid || !token.firebase?.sign_in_provider || token.firebase.sign_in_provider === 'anonymous') fail(403, 'registered_account_required');
  return identifier(token.uid);
}

function createDeviceSecurity({ firestore, rtdb, now = Date.now, randomBytes = crypto.randomBytes }) {
  const deviceRef = (id) => firestore.collection('devices').doc(identifier(id));
  const mirrorRef = (uid, id) => firestore.collection('users').doc(uid).collection('devices').doc(id);
  async function limit(uid, action, maximum, windowMs) {
    const ref = firestore.collection('security_rate_limits').doc(hash(`${uid}:${action}`));
    await firestore.runTransaction(async (tx) => {
      const snap = await tx.get(ref); const data = snap.data(); const time = now();
      const current = data && data.reset_at > time ? data : { count: 0, reset_at: time + windowMs };
      if (current.count >= maximum) fail(429, 'rate_limited');
      tx.set(ref, { count: current.count + 1, reset_at: current.reset_at });
    });
  }
  // Versioned whole-device ACLs prevent delayed synchronization restoring revoked grants.
  async function syncDevice(id) {
    const issuedAt = now();
    // The version and member map share one document, so one snapshot is atomic.
    const d = (await deviceRef(id).get()).data();
    const members = {};
    if (d?.active === true) {
      for (const [uid, role] of Object.entries(d.members || {})) {
        if (role === 'shared' || (role === 'owner' && d.owner_uid === uid)) members[uid] = { read: true, control: role === 'owner' };
      }
    }
    const value = { version: d?.auth_version || 0, expires_at: issuedAt + 90000, members };
    await rtdb.ref(`authorization/${id}`).transaction((current) => {
      if (current && (current.version > value.version || (current.version === value.version && current.expires_at > value.expires_at))) return;
      return value;
    });
  }
  async function mutate(id, operation) {
    const result = await firestore.runTransaction(async (tx) => {
      const ref = deviceRef(id); const snap = await tx.get(ref);
      if (!snap.exists) fail(404, 'device_unavailable');
      const d = snap.data(); const result = await operation(tx, ref, d);
      tx.update(ref, { auth_version: (d.auth_version || 0) + 1 });
      return result;
    });
    try { await syncDevice(id); } catch { fail(503, 'access_sync_pending'); }
    return result;
  }
  async function execute(uid, method, path, body) {
    identifier(uid); await limit(uid, 'api', 60, 60000);
    if (method === 'GET' && path === '/api/devices') {
      const mirrors = await firestore.collection('users').doc(uid).collection('devices').get(); const devices = [];
      for (const doc of mirrors.docs) {
        const d = (await deviceRef(doc.id).get()).data(); const role = d?.members?.[uid];
        if (d?.active === true && (role === 'shared' || (role === 'owner' && d.owner_uid === uid))) devices.push({ device_id: doc.id, name: d.name || doc.id, role });
      }
      return { devices };
    }
    if (method === 'POST' && path === '/api/pairing/redeem') {
      fields(body, ['code', 'name']); name(body.name); await limit(uid, 'redeem', 5, 15 * 60000);
      if (typeof body.code !== 'string' || !/^PC-[A-F0-9]{32}$/.test(body.code)) fail(400, 'invalid_pairing_code');
      const codeRef = firestore.collection('pairing_codes').doc(hash(body.code)); let id;
      await firestore.runTransaction(async (tx) => {
        const code = (await tx.get(codeRef)).data();
        if (!code) fail(404, 'invalid_pairing_code');
        if (code.used_by) fail(409, 'pairing_code_used');
        if (code.expires_at <= now()) fail(410, 'pairing_code_expired');
        id = identifier(code.device_id); const ref = deviceRef(id); const d = (await tx.get(ref)).data(); owner(d, code.owner_uid);
        if ((d.pairing_epoch || 0) !== code.epoch) fail(410, 'pairing_code_expired');
        if (d.owner_uid === uid) fail(409, 'already_owner');
        if (Object.keys(d.members || {}).length >= 50 && !d.members?.[uid]) fail(409, 'member_limit');
        tx.update(ref, { members: { ...d.members, [uid]: 'shared' }, auth_version: (d.auth_version || 0) + 1 });
        tx.set(mirrorRef(uid, id), { name: d.name || id, role: 'shared' });
        tx.update(codeRef, { used_by: uid, used_at: now() });
      });
      try { await syncDevice(id); } catch { fail(503, 'access_sync_pending'); }
      return { device_id: id, role: 'shared' };
    }
    const match = path.match(/^\/api\/devices\/([A-Za-z0-9_-]{1,128})(?:\/(validate|claim|pairing|members)(?:\/([A-Za-z0-9_-]{1,128}))?)?$/);
    if (!match) fail(404, 'not_found');
    const [, id, action, target] = match;
    if (method === 'POST' && action === 'validate' && !target) {
      fields(body, []); await limit(uid, 'validate', 10, 60000); const d = (await deviceRef(id).get()).data();
      return { claimable: !!(d?.active === true && (!d.owner_uid || d.owner_uid === uid)) };
    }
    if (method === 'POST' && action === 'claim' && !target) {
      fields(body, ['name']); const displayName = name(body.name);
      await mutate(id, async (tx, ref, d) => {
        if (d.active !== true || (d.owner_uid && d.owner_uid !== uid)) fail(409, 'device_unavailable');
        tx.update(ref, { owner_uid: uid, name: displayName, members: { ...d.members, [uid]: 'owner' } });
        for (const member of new Set([...Object.keys(d.members || {}), uid])) tx.set(mirrorRef(member, id), { name: displayName, role: member === uid ? 'owner' : d.members[member] });
      });
      return { device_id: id, role: 'owner' };
    }
    if (method === 'POST' && action === 'pairing' && !target) {
      fields(body, []); await limit(uid, 'generate', 5, 10 * 60000);
      const code = `PC-${randomBytes(16).toString('hex').toUpperCase()}`; const expires = now() + 10 * 60000;
      await firestore.runTransaction(async (tx) => {
        const ref = deviceRef(id); const d = (await tx.get(ref)).data(); owner(d, uid); const epoch = (d.pairing_epoch || 0) + 1;
        tx.update(ref, { pairing_epoch: epoch });
        tx.create(firestore.collection('pairing_codes').doc(hash(code)), { device_id: id, owner_uid: uid, epoch, expires_at: expires, created_at: now() });
      });
      return { code, expires_at: expires };
    }
    if (method === 'GET' && action === 'members' && !target) {
      const d = (await deviceRef(id).get()).data(); owner(d, uid);
      return { members: Object.entries(d.members || {}).map(([memberUid, role]) => ({ uid: memberUid, role })) };
    }
    if (method === 'PATCH' && !action) {
      fields(body, ['name']); const displayName = name(body.name);
      await mutate(id, async (tx, ref, d) => {
        owner(d, uid); tx.update(ref, { name: displayName });
        for (const [member, role] of Object.entries(d.members)) tx.set(mirrorRef(member, id), { name: displayName, role });
      });
      return { device_id: id, name: displayName };
    }
    if (method === 'DELETE' && (!action || (action === 'members' && target))) {
      fields(body, []); const removeUid = target || uid;
      await mutate(id, async (tx, ref, d) => {
        if (target) { owner(d, uid); if (removeUid === d.owner_uid) fail(403, 'cannot_revoke_owner'); }
        else if (!['owner', 'shared'].includes(d.members?.[uid])) fail(403, 'membership_required');
        const members = { ...d.members }; delete members[removeUid];
        tx.update(ref, { members, ...(removeUid === d.owner_uid ? { pairing_epoch: (d.pairing_epoch || 0) + 1 } : {}) }); tx.delete(mirrorRef(removeUid, id));
      });
      return { removed: true };
    }
    fail(404, 'not_found');
  }
  async function syncAll() { const devices = await firestore.collection('devices').get(); for (const doc of devices.docs) await syncDevice(doc.id); }
  return { execute, syncAll, syncDevice };
}
function createIpLimiter(now = Date.now) {
  const buckets = new Map();
  return (ip) => {
    const time = now(); for (const [key, bucket] of buckets) if (bucket.reset <= time) buckets.delete(key);
    const key = hash(ip || 'unknown'); const bucket = buckets.get(key) || { count: 0, reset: time + 60000 };
    if (bucket.count >= 120 || (!buckets.has(key) && buckets.size >= 10000)) fail(429, 'rate_limited');
    bucket.count++; buckets.set(key, bucket);
  };
}
module.exports = { ApiError, authenticate, createDeviceSecurity, createIpLimiter, identifier, fields };
