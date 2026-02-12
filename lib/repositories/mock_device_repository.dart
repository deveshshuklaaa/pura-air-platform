import 'dart:async';

import '../data/mock_data.dart';
import '../models/device.dart';
import 'device_repository.dart';

class MockDeviceRepository implements DeviceRepository {
  final _controller = StreamController<List<Device>>.broadcast();
  final List<Device> _devices = [...MockData.devices()];
  final Set<String> _claimedIds = {};

  MockDeviceRepository() {
    _claimedIds.addAll(_devices.map((device) => device.deviceId));
    _controller.add(_devices);
  }

  @override
  Stream<List<Device>> watchDevices() => _controller.stream;

  @override
  Future<void> updateControls({
    required String deviceId,
    required bool manual,
    required int fanLevel,
    required bool mist,
  }) async {
    final index = _devices.indexWhere((device) => device.deviceId == deviceId);
    if (index == -1) return;
    final device = _devices[index];
    _devices[index] = Device(
      deviceId: device.deviceId,
      name: device.name,
      online: device.online,
      lastSeen: device.lastSeen,
      snapshot: device.snapshot.copyWith(
        mode: manual ? 'MANUAL' : 'AUTO',
        fanLevel: fanLevel,
        mist: mist,
      ),
    );
    _controller.add(List<Device>.from(_devices));
  }

  @override
  Future<bool> validateDeviceId(String deviceId) async {
    if (deviceId.isEmpty) return false;
    if (_devices.any((device) => device.deviceId == deviceId)) return true;
    return !_claimedIds.contains(deviceId);
  }

  @override
  Future<void> addDevice({required String deviceId, required String name}) async {
    if (_claimedIds.contains(deviceId) &&
        !_devices.any((device) => device.deviceId == deviceId)) {
      return;
    }
    if (_devices.any((device) => device.deviceId == deviceId)) return;
    final base = MockData.devices().first.snapshot;
    _devices.add(Device(
      deviceId: deviceId,
      name: name,
      online: true,
      lastSeen: DateTime.now(),
      snapshot: base,
    ));
    _claimedIds.add(deviceId);
    _controller.add(List<Device>.from(_devices));
  }

  @override
  Future<void> addDeviceWithPairingCode({
    required String pairingCode,
    required String name,
  }) async {
    final deviceId = pairingCode.startsWith('PA-')
        ? pairingCode
        : 'PA-${pairingCode.toUpperCase()}';
    await addDevice(deviceId: deviceId, name: name);
  }

  @override
  Future<String> createPairingCode({required String deviceId}) async {
    return 'PAIR-${deviceId.replaceAll('PA-', '')}';
  }

  @override
  Future<void> renameDevice({required String deviceId, required String name}) async {
    final index = _devices.indexWhere((device) => device.deviceId == deviceId);
    if (index == -1) return;
    final device = _devices[index];
    _devices[index] = Device(
      deviceId: device.deviceId,
      name: name,
      online: device.online,
      lastSeen: device.lastSeen,
      snapshot: device.snapshot,
    );
    _controller.add(List<Device>.from(_devices));
  }

  @override
  Future<void> removeDevice({required String deviceId}) async {
    _devices.removeWhere((device) => device.deviceId == deviceId);
    _controller.add(List<Device>.from(_devices));
  }
}
