'use strict';

function getDeviceHistoryCollection(firestore, deviceId) {
  return firestore.collection('devices').doc(deviceId).collection('history');
}

async function saveHistoryRecord(firestore, deviceId, record) {
  const historyCollection = getDeviceHistoryCollection(firestore, deviceId);
  const docId = String(record.timestamp);

  await historyCollection.doc(docId).set(record, { merge: true });
}

async function getRecentHistory(firestore, deviceId, limit = 30) {
  const historyCollection = getDeviceHistoryCollection(firestore, deviceId);

  const snapshot = await historyCollection.orderBy('timestamp', 'desc').limit(limit).get();

  const docs = snapshot.docs
    .map((doc) => doc.data())
    .filter((item) => Number.isFinite(item?.timestamp) && Number.isFinite(item?.aqi))
    .sort((a, b) => a.timestamp - b.timestamp);

  return docs;
}

module.exports = {
  saveHistoryRecord,
  getRecentHistory,
};
