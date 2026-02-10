import '../models/device.dart';
import '../models/device_snapshot.dart';

class MockData {
  static List<Device> devices() {
    final now = DateTime.now();
    return [
      Device(
        deviceId: 'PA-012',
        name: 'Living Room',
        online: true,
        lastSeen: now.subtract(const Duration(minutes: 2)),
        snapshot: const DeviceSnapshot(
          co2: 980,
          pm25Avg: 42,
          aqi: 68,
          aqiCategory: 'Moderate',
          aqiTrend: 12,
          gasIndex: 1.3,
          fanLevel: 2,
          mist: false,
          mode: 'AUTO',
          humidity: 44.5,
          temperature: 23.4,
        ),
      ),
      Device(
        deviceId: 'PA-014',
        name: 'Bedroom',
        online: true,
        lastSeen: now.subtract(const Duration(minutes: 6)),
        snapshot: const DeviceSnapshot(
          co2: 760,
          pm25Avg: 18,
          aqi: 32,
          aqiCategory: 'Good',
          aqiTrend: -5,
          gasIndex: 0.8,
          fanLevel: 1,
          mist: true,
          mode: 'AUTO',
          humidity: 41.2,
          temperature: 22.0,
        ),
      ),
      Device(
        deviceId: 'PA-017',
        name: 'Kitchen',
        online: false,
        lastSeen: now.subtract(const Duration(hours: 3)),
        snapshot: const DeviceSnapshot(
          co2: 1320,
          pm25Avg: 88,
          aqi: 142,
          aqiCategory: 'Unhealthy',
          aqiTrend: 20,
          gasIndex: 2.4,
          fanLevel: 3,
          mist: false,
          mode: 'MANUAL',
          humidity: 52.7,
          temperature: 25.8,
        ),
      ),
    ];
  }
}
