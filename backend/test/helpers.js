'use strict';
// Transactional in-memory test double; emulator tests separately exercise the real SDK.
function fixture() {
  const records = new Map([['devices/PA-TEST', { active: true, owner_uid: null }]]);
  const acl = new Map(); let chain = Promise.resolve(); let time = Date.now();
  function ref(path) {
    return { path, id: path.split('/').at(-1), collection: (part) => collection(`${path}/${part}`),
      get: async () => snapshot(path, records), set: async (data) => records.set(path, structuredClone(data)) };
  }
  function snapshot(path, map) {
    return { exists: map.has(path), id: path.split('/').at(-1), data: () => structuredClone(map.get(path)) };
  }
  function collection(path, ordering, direction, count) {
    return { doc: (id) => ref(path+'/'+id),
      orderBy: (field, dir) => collection(path, field, dir, count),
      limit: (n) => collection(path, ordering, direction, n),
      get: async () => {
        let docs = [...records.keys()].filter((key) => key.startsWith(path+'/') && key.split('/').length === path.split('/').length + 1).map((key) => snapshot(key, records));
        if (ordering) docs = docs.filter(d=>d.data()[ordering] !== undefined).sort((a,b)=>(a.data()[ordering]-b.data()[ordering])*(direction==='desc'?-1:1));
        if (count) docs=docs.slice(0,count);
        return { docs };
      } };
  }
  const firestore = { collection, runTransaction: (fn) => {
    const result = chain.then(async () => {
      const staged = new Map(records);
      const tx = { get: async (r) => snapshot(r.path, staged),
        set: (r, data) => staged.set(r.path, structuredClone(data)),
        create: (r, data) => { if (staged.has(r.path)) throw Error('exists'); staged.set(r.path, structuredClone(data)); },
        update: (r, data) => staged.set(r.path, { ...staged.get(r.path), ...structuredClone(data) }),
        delete: (r) => staged.delete(r.path) };
      const value = await fn(tx); records.clear(); for (const item of staged) records.set(...item); return value;
    }); chain = result.catch(() => {}); return result;
  } };
  const rtdb = { ref: (path) => ({ transaction: async (fn) => {
    const next = fn(acl.get(path) || null); if (next !== undefined) acl.set(path, next);
  } }) };
  return { firestore, rtdb, records, acl, now: () => time, advance: (ms) => { time += ms; } };
}
module.exports = { fixture };
