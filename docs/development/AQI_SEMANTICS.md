# PURA AIR particulate indicator — prototype v1

Decision recorded 21 October 2026 before changing calculations. No justified requirement for an official AQI standard exists in the repository. The application will label its value **PURA particulate indicator (prototype)**, never official CPCB or current US EPA AQI.

Raw PM2.5/PM10 (µg/m³) are measurements. The indicator is an instantaneous two-particulate heuristic, not a calibrated exposure estimate or national overall AQI. PMS5003, SCD40 CO₂ and an MQ-135 response do not establish CPCB pollutant coverage; CO₂ is not CO, and an uncalibrated gas response cannot substitute for a required pollutant. Official indices require their own pollutant coverage, calibration, averaging, completeness and precision rules. The existing older EPA-like table is retained solely as an explicit prototype continuity choice.

Truncate validated PM2.5 to one decimal place and PM10 to an integer **for index calculation only**. Preserve the original fractional measurements in history. Interpolate linearly within each range, round each sub-index to nearest integer, then take the maximum. Both finite, nonnegative PM measurements are required; otherwise return unavailable, never zero. Concentrations above the final breakpoint saturate at 500 and do not assert official extreme-AQI semantics.

| Indicator range | PM2.5 range (µg/m³) | PM10 range (µg/m³) |
| --- | --- | --- |
| 0–50 | 0–12.0 | 0–54 |
| 51–100 | 12.1–35.4 | 55–154 |
| 101–150 | 35.5–55.4 | 155–254 |
| 151–200 | 55.5–150.4 | 255–354 |
| 201–300 | 150.5–250.4 | 355–424 |
| 301–500 | 250.5–500.4 | 425–604 |

Precision truncation removes the old fractional gaps (e.g. 12.05 and 54.5) without altering raw values. Version identifier: `pura-particulate-v1`. Display numeric bands as prototype bands; do not use a reassuring “Good” label for absent readings. Existing undocumented legacy `aqi` values are not automatically relabelled as verified v1 values.

The regression forecast uses unique persisted v1 history points, measurement timestamps and explicit 10/30-minute horizons, is clipped to 0–500, and is unavailable until at least two distinct timestamps exist. It does not double-count the freshly saved point after restart. No measured error/clinical/environmental accuracy claim is made. Future index revisions can recompute from retained raw fields; no production history migration is performed here.

References for the distinction, not claims of compliance: [CPCB index explanation from the Indian Economic Service](https://ies.gov.in/arthapedia/concept/national-air-quality-index), [EPA technical assistance document](https://document.airnow.gov/technical-assistance-document-for-the-reporting-of-daily-air-quailty.pdf). These are the primary sources reviewed in Phase 0; this prototype deliberately does not implement their complete requirements.
