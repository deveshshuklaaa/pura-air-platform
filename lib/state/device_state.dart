import 'package:cloud_firestore/cloud_firestore.dart';
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

final selectedDeviceHistoryProvider = StreamProvider<List<Map<String, double>>>(
  (ref) {
    final device = ref.watch(selectedDeviceProvider);
    if (device == null) {
      return Stream.value(<Map<String, double>>[]);
    }

    return FirebaseFirestore.instance
        .collection('devices')
        .doc(device.deviceId)
        .collection('history')
        .orderBy('server_received_at', descending: true)
        .limit(30)
        .snapshots()
        .map((snapshot) {
      final rows = snapshot.docs
          .map((doc) => doc.data())
          .map((data) {
            final timestamp = _asDouble(data['timestamp']);
            final aqi = _asDouble(data['aqi']);
            final pm25 = _asDouble(data['pm25']);
            final pm10 = _asDouble(data['pm10']);

            if (timestamp == null ||
                aqi == null ||
                pm25 == null ||
                pm10 == null) {
              return null;
            }

            return <String, double>{
              'timestamp': timestamp,
              'aqi': aqi,
              'pm25': pm25,
              'pm10': pm10,
            };
          })
          .whereType<Map<String, double>>()
          .toList()
        ..sort((a, b) => (a['timestamp']!).compareTo(b['timestamp']!));

      return rows;
    });
  },
);

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
