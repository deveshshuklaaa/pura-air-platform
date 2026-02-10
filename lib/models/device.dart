import 'device_snapshot.dart';

class Device {
  final String deviceId;
  final String name;
  final bool online;
  final DateTime lastSeen;
  final DeviceSnapshot snapshot;

  const Device({
    required this.deviceId,
    required this.name,
    required this.online,
    required this.lastSeen,
    required this.snapshot,
  });
}
