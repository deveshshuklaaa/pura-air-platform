'use strict';

const PM25_BREAKPOINTS = [
  { cLow: 0.0, cHigh: 12.0, iLow: 0, iHigh: 50 },
  { cLow: 12.1, cHigh: 35.4, iLow: 51, iHigh: 100 },
  { cLow: 35.5, cHigh: 55.4, iLow: 101, iHigh: 150 },
  { cLow: 55.5, cHigh: 150.4, iLow: 151, iHigh: 200 },
  { cLow: 150.5, cHigh: 250.4, iLow: 201, iHigh: 300 },
  { cLow: 250.5, cHigh: 500.4, iLow: 301, iHigh: 500 },
];

const PM10_BREAKPOINTS = [
  { cLow: 0, cHigh: 54, iLow: 0, iHigh: 50 },
  { cLow: 55, cHigh: 154, iLow: 51, iHigh: 100 },
  { cLow: 155, cHigh: 254, iLow: 101, iHigh: 150 },
  { cLow: 255, cHigh: 354, iLow: 151, iHigh: 200 },
  { cLow: 355, cHigh: 424, iLow: 201, iHigh: 300 },
  { cLow: 425, cHigh: 604, iLow: 301, iHigh: 500 },
];

function isValidNumber(value) {
  return Number.isFinite(value);
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function interpolateAqi(concentration, bp) {
  const c = concentration;
  return ((bp.iHigh - bp.iLow) / (bp.cHigh - bp.cLow)) * (c - bp.cLow) + bp.iLow;
}

function calculateSubIndex(concentration, breakpoints) {
  if (!isValidNumber(concentration)) {
    return null;
  }

  const capped = clamp(concentration, breakpoints[0].cLow, breakpoints[breakpoints.length - 1].cHigh);
  const bp = breakpoints.find((item) => capped >= item.cLow && capped <= item.cHigh);

  if (!bp) {
    return null;
  }

  return Math.round(interpolateAqi(capped, bp));
}

function calculateAqi({ pm25, pm10 }) {
  const aqiPm25 = calculateSubIndex(pm25, PM25_BREAKPOINTS);
  const aqiPm10 = calculateSubIndex(pm10, PM10_BREAKPOINTS);

  if (aqiPm25 === null || aqiPm10 === null) {
    return null;
  }

  const dominantPollutant = aqiPm25 >= aqiPm10 ? 'pm25' : 'pm10';
  const aqi = Math.max(aqiPm25, aqiPm10);

  return {
    aqi,
    dominantPollutant,
    aqiPm25,
    aqiPm10,
  };
}

module.exports = {
  calculateAqi,
  isValidNumber,
};
