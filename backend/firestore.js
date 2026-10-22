'use strict';

function getDeviceHistoryCollection(firestore, deviceId) {
  return firestore.collection('devices').doc(deviceId).collection('history');
}

async function saveHistoryRecord(firestore, deviceId, record) {
  const { identity } = require('./telemetry-contract');
  if (typeof record.event_id !== 'string') throw Error('stable_event_id_required');
  await getDeviceHistoryCollection(firestore, deviceId).doc(identity(deviceId, record.event_id)).set({
    ...record, created_at: record.server_received_at,
  });
}

async function getRecentHistory(firestore, deviceId, limit = 60) {
  const snapshot = await getDeviceHistoryCollection(firestore, deviceId).orderBy('timestamp', 'desc').limit(limit).get();
  return snapshot.docs.map(doc => doc.data()).filter(item => Number.isFinite(item.timestamp))
    .sort((a,b) => a.timestamp - b.timestamp || (a.accepted_order || 0) - (b.accepted_order || 0));
}

async function saveDeadLetterRecord(firestore, record) {
  await firestore.collection('ingestion_dead_letter').add({
    ...record,
    created_at: Date.now(),
  });
}

async function cleanupOldHistoryForDevice(firestore, deviceId, cutoffTimestamp, batchSize = 250) {
  const historyCollection = getDeviceHistoryCollection(firestore, deviceId);
  const primarySnapshot = await historyCollection
    .where('server_received_at', '<', cutoffTimestamp)
    .orderBy('server_received_at', 'asc')
    .limit(batchSize)
    .get();

  // Never delete newly received data based only on a producer's old clock.
  const refs = new Map(primarySnapshot.docs.map(doc => [doc.ref.path, doc.ref]));

  if (refs.size === 0) {
    return 0;
  }

  const batch = firestore.batch();
  for (const ref of refs.values()) {
    batch.delete(ref);
  }
  await batch.commit();

  return refs.size;
}

module.exports = {
  saveHistoryRecord,
  getRecentHistory,
  saveDeadLetterRecord,
  cleanupOldHistoryForDevice,
};
