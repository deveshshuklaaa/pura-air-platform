'use strict';

function getDeviceHistoryCollection(firestore, deviceId) {
  return firestore.collection('devices').doc(deviceId).collection('history');
}

async function saveHistoryRecord(firestore, deviceId, record) {
  const historyCollection = getDeviceHistoryCollection(firestore, deviceId);
  const explicitId =
    typeof record.idempotency_key === 'string' && record.idempotency_key
      ? record.idempotency_key
      : null;
  const docRef = explicitId ? historyCollection.doc(explicitId) : historyCollection.doc();
  const payload = {
    ...record,
    created_at: Date.now(),
  };

  await docRef.set(payload, { merge: true });
}

async function getRecentHistory(firestore, deviceId, limit = 30) {
  const historyCollection = getDeviceHistoryCollection(firestore, deviceId);

  const snapshot = await historyCollection.orderBy('server_received_at', 'desc').limit(limit).get();

  const docs = snapshot.docs
    .map((doc) => doc.data())
    .map((item) => {
      if (!Number.isFinite(item?.timestamp) || !Number.isFinite(item?.aqi)) {
        return null;
      }
      return {
        ...item,
        server_received_at: Number.isFinite(item?.server_received_at)
          ? item.server_received_at
          : item.timestamp,
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.server_received_at - b.server_received_at);

  return docs;
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

  const legacySnapshot = await historyCollection
    .where('timestamp', '<', cutoffTimestamp)
    .orderBy('timestamp', 'asc')
    .limit(batchSize)
    .get();

  const refs = new Map();
  for (const doc of primarySnapshot.docs) {
    refs.set(doc.ref.path, doc.ref);
  }
  for (const doc of legacySnapshot.docs) {
    refs.set(doc.ref.path, doc.ref);
  }

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
