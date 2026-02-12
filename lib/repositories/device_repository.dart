import '../models/device.dart';

abstract class DeviceRepository {
  Stream<List<Device>> watchDevices();

  Future<void> updateControls({
    required String deviceId,
    required bool manual,
    required int fanLevel,
    required bool mist,
  });

  Future<bool> validateDeviceId(String deviceId);

  Future<void> addDevice({
    required String deviceId,
    required String name,
  });

  Future<void> addDeviceWithPairingCode({
    required String pairingCode,
    required String name,
  });

  Future<String> createPairingCode({
    required String deviceId,
  });

  Future<void> renameDevice({
    required String deviceId,
    required String name,
  });

  Future<void> removeDevice({
    required String deviceId,
  });
}
