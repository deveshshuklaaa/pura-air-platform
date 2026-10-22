import 'device.dart';
import 'device_snapshot.dart';

const indicatorVersion = 'pura-particulate-v1';

double? measurement(dynamic value,
        {double min = 0, double max = double.infinity}) =>
    value is num && value.isFinite && value >= min && value <= max
        ? value.toDouble()
        : null;
DateTime? telemetryTime(dynamic value) {
  if (value is! num ||
      !value.isFinite ||
      value % 1 != 0 ||
      value <= 0 ||
      value > 8640000000000000) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value.toInt());
}

int? indicatorValue(Map<String, dynamic>? data, String key) {
  if (data?['indicator_version'] != indicatorVersion) return null;
  final value = measurement(data?[key]);
  return value != null && value >= 0 && value <= 500 ? value.round() : null;
}

class TelemetryReading {
  final DateTime timestamp;
  final double? pm25, pm10;
  final int? indicator;
  final bool isTestData;
  final String? eventId;
  const TelemetryReading(
      {required this.timestamp,
      this.pm25,
      this.pm10,
      this.indicator,
      this.isTestData = false,
      this.eventId});
  static TelemetryReading? parse(Map<String, dynamic> data) {
    final time = telemetryTime(data['timestamp']);
    if (time == null) return null;
    return TelemetryReading(
        timestamp: time,
        pm25: measurement(data['pm25'], max: 5000),
        pm10: measurement(data['pm10'], max: 5000),
        indicator: indicatorValue(data, 'particulate_indicator'),
        isTestData: data['source'] == 'simulator',
        eventId:
            data['event_id'] is String ? data['event_id'] as String : null);
  }
}

Device mapTelemetryDevice(
    {required String deviceId,
    required Map<String, dynamic> metadata,
    Map<String, dynamic>? state,
    Map<String, dynamic>? forecast,
    required DateTime now,
    bool loading = false,
    String? error}) {
  final measured =
      telemetryTime(state?['timestamp'] ?? state?['device_timestamp']);
  final received =
      telemetryTime(state?['server_received_at'] ?? state?['last_updated']);
  final aqi = indicatorValue(state, 'particulate_indicator');
  final matchingForecast = forecast?['source_event_id'] == state?['event_id'] &&
      telemetryTime(forecast?['calculated_at']) != null;
  final forecast10 =
      matchingForecast ? indicatorValue(forecast, 'aqi_10min') : null;
  final forecast30 =
      matchingForecast ? indicatorValue(forecast, 'aqi_30min') : null;
  bool recent(DateTime? time) =>
      time != null &&
      now.difference(time).inMilliseconds >= -300000 &&
      now.difference(time) <= const Duration(minutes: 2);
  return Device(
      deviceId: deviceId,
      name:
          metadata['name'] is String ? metadata['name'] as String : 'PURA AIR',
      role: metadata['role'] == 'owner' ? 'owner' : 'shared',
      online: error == null && recent(measured) && recent(received),
      lastSeen: measured ?? DateTime.fromMillisecondsSinceEpoch(0),
      snapshot: DeviceSnapshot(
          co2: measurement(state?['co2'], max: 50000),
          pm25Avg: measurement(state?['pm25'], max: 5000),
          pm10: measurement(state?['pm10'], max: 5000),
          aqi: aqi,
          aqiCategory:
              aqi == null ? 'Unavailable' : 'Prototype band ${aqi ~/ 100 + 1}',
          aqiTrend: aqi == null || forecast10 == null ? null : forecast10 - aqi,
          gasIndex: measurement(state?['gas_index'], max: 1000),
          fanLevel: (measurement(state?['fan_level']) ?? 1).round().clamp(1, 5),
          mist: state?['mist'] == true,
          mode: state?['mode'] == 'MANUAL' ? 'MANUAL' : 'AUTO',
          humidity: measurement(state?['humidity'], max: 100),
          temperature: measurement(state?['temperature'], min: -40, max: 85),
          forecast10: forecast10,
          forecast30: forecast30,
          forecastAt: telemetryTime(forecast?['calculated_at']),
          measuredAt: measured,
          receivedAt: received,
          eventId: state?['event_id'] is String
              ? state!['event_id'] as String
              : null,
          loading: loading,
          error: error,
          isTestData: state?['source'] == 'simulator'));
}
