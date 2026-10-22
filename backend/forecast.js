'use strict';

const TEN_MINUTES_MS = 10 * 60 * 1000;
const THIRTY_MINUTES_MS = 30 * 60 * 1000;

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function buildLinearRegression(points) {
  const n = points.length;
  if (n < 2) {
    return null;
  }

  const x0 = points[0].timestamp;
  const normalized = points.map((point) => ({
    x: (point.timestamp - x0) / 60000,
    y: point.aqi,
  }));

  let sumX = 0;
  let sumY = 0;
  let sumXY = 0;
  let sumX2 = 0;

  for (const point of normalized) {
    sumX += point.x;
    sumY += point.y;
    sumXY += point.x * point.y;
    sumX2 += point.x * point.x;
  }

  const denominator = n * sumX2 - sumX * sumX;
  if (denominator === 0) {
    return null;
  }

  const slope = (n * sumXY - sumX * sumY) / denominator;
  const intercept = (sumY - slope * sumX) / n;

  return {
    slope,
    intercept,
    x0,
  };
}

function predictAqi(model, timestamp) {
  const x = (timestamp - model.x0) / 60000;
  const predicted = model.slope * x + model.intercept;
  return Math.round(clamp(predicted, 0, 500));
}

function buildForecast(history, baseTimestamp, calculatedAt = Date.now()) {
  if (!Array.isArray(history) || history.length === 0 || !Number.isFinite(baseTimestamp)) {
    return null;
  }

  history = history.filter((p) => Number.isFinite(p.timestamp) && Number.isFinite(p.aqi));
  if (new Set(history.map((p) => p.timestamp)).size < 2) return null;
  const model = buildLinearRegression(history);

  if (!model) {
    const latest = history[history.length - 1];
    const fallback = Math.round(clamp(latest.aqi, 0, 500));
    return {
      aqi_10min: fallback,
      aqi_30min: fallback,
      calculated_at: calculatedAt,
      base_timestamp: baseTimestamp,
      sample_count: history.length,
    };
  }

  return {
    aqi_10min: predictAqi(model, baseTimestamp + TEN_MINUTES_MS),
    aqi_30min: predictAqi(model, baseTimestamp + THIRTY_MINUTES_MS),
    calculated_at: calculatedAt,
  };
}

module.exports = {
  buildForecast,
};
