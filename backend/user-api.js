'use strict';
const { ApiError, authenticate, createDeviceSecurity, createIpLimiter } = require('./device-security');

function createUserApiHandler(services, { readRequestBody, sendJson }, options = {}) {
  const security = options.security || createDeviceSecurity(services);
  const checkIp = createIpLimiter();
  const allowedOrigins = (process.env.API_ALLOWED_ORIGINS || '').split(',').filter(Boolean);
  return async (req, res, pathname) => {
    try {
      checkIp(req.socket?.remoteAddress); // Never trust client-supplied X-Forwarded-For.
      const origin = req.headers.origin;
      if (origin) {
        if (!allowedOrigins.includes(origin)) throw new ApiError(403, 'origin_not_allowed');
        res.setHeader('Access-Control-Allow-Origin', origin);
        res.setHeader('Vary', 'Origin');
      }
      if (req.method === 'OPTIONS') {
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
        sendJson(res, 204, {}); return;
      }
      const uid = await authenticate(services.auth || services.admin.auth(), req.headers.authorization);
      const body = ['POST', 'PATCH', 'DELETE'].includes(req.method) ? await readRequestBody(req) : {};
      const result = await security.execute(uid, req.method, pathname, body);
      sendJson(res, 200, result);
    } catch (error) {
      // Token/SDK errors, keys and request bodies must never enter responses or logs.
      const status = error instanceof ApiError ? error.status : (error.statusCode || 500);
      if (status === 429) res.setHeader('Retry-After', '60');
      sendJson(res, status, { error: error instanceof ApiError ? error.code : (status === 400 ? 'invalid_json' : 'service_unavailable') });
    }
  };
}
module.exports = { createUserApiHandler };
