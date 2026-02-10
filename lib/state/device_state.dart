import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../repositories/device_repository.dart';
import '../repositories/firestore_device_repository.dart';
import '../repositories/mock_device_repository.dart';

final useFirebaseProvider = Provider<bool>((ref) {
  return Firebase.apps.isNotEmpty;
});

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirestoreDeviceRepository() : MockDeviceRepository();
});

final devicesStreamProvider = StreamProvider<List<Device>>((ref) {
  final repo = ref.watch(deviceRepositoryProvider);
  return repo.watchDevices();
});

final selectedDeviceIdProvider = StateProvider<String?>((ref) => null);

final selectedDeviceProvider = Provider<Device?>((ref) {
  final devicesAsync = ref.watch(devicesStreamProvider);
  final selectedId = ref.watch(selectedDeviceIdProvider);

  return devicesAsync.maybeWhen(
    data: (devices) {
      if (devices.isEmpty) return null;
      return devices.firstWhere(
        (device) => device.deviceId == selectedId,
        orElse: () => devices.first,
      );
    },
    orElse: () => null,
  );
});
