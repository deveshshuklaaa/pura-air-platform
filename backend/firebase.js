'use strict';

const admin = require('firebase-admin');
const fs = require('node:fs');

function buildCredential() {
  let projectIdFromCredential = null;

  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      const parsed = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
      projectIdFromCredential = parsed.project_id || null;
      return {
        credential: admin.credential.cert(parsed),
        projectIdFromCredential,
      };
    } catch (error) {
      throw new Error(`Invalid FIREBASE_SERVICE_ACCOUNT_JSON: ${error.message}`);
    }
  }

  if (process.env.FIREBASE_SERVICE_ACCOUNT_PATH) {
    try {
      const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
      const keyJson = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
      projectIdFromCredential = keyJson.project_id || null;
      return {
        credential: admin.credential.cert(keyJson),
        projectIdFromCredential,
      };
    } catch (error) {
      throw new Error(`Unable to read FIREBASE_SERVICE_ACCOUNT_PATH: ${error.message}`);
    }
  }

  return {
    credential: admin.credential.applicationDefault(),
    projectIdFromCredential,
  };
}

function resolveDatabaseURL(projectId) {
  if (process.env.FIREBASE_DATABASE_URL) {
    return process.env.FIREBASE_DATABASE_URL;
  }

  if (projectId) {
    return `https://${projectId}-default-rtdb.firebaseio.com`;
  }

  throw new Error(
    'Missing FIREBASE_DATABASE_URL and unable to infer projectId. Set FIREBASE_DATABASE_URL explicitly.'
  );
}

function initFirebase() {
  if (admin.apps.length > 0) {
    const app = admin.app();
    return {
      admin,
      app,
      rtdb: app.database(),
      firestore: app.firestore(),
    };
  }

  const { credential, projectIdFromCredential } = buildCredential();

  const projectId =
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    projectIdFromCredential;

  const app = admin.initializeApp({
    credential,
    databaseURL: resolveDatabaseURL(projectId),
  });

  return {
    admin,
    app,
    rtdb: app.database(),
    firestore: app.firestore(),
  };
}

module.exports = {
  initFirebase,
};
