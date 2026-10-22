import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/device.dart';
import '../services/device_api_client.dart';
import '../models/telemetry_reading.dart';
import 'device_repository.dart';

class FirestoreDeviceRepository implements DeviceRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;
  final DeviceApiClient _api;

  FirestoreDeviceRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseDatabase? database,
    DeviceApiClient? api,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _database = database ?? FirebaseDatabase.instance,
        _api = api ?? DeviceApiClient();

  @override
  Stream<List<Device>> watchDevices() {
    return Stream.multi((controller) {
      StreamSubscription<User?>? authSub;
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? userDevicesSub;
      final stateSubs = <String, StreamSubscription<DatabaseEvent>>{};
      final forecastSubs = <String, StreamSubscription<DatabaseEvent>>{};

      final userDevices = <String, Map<String, dynamic>>{};
      final liveStates = <String, Map<String, dynamic>>{};
      final liveForecasts = <String, Map<String, dynamic>>{};
      final errors = <String, String>{};
      Timer? freshnessTimer;
      var closed = false;

      Future<void> cancelRealtimeFor(String deviceId) async {
        await stateSubs.remove(deviceId)?.cancel();
        await forecastSubs.remove(deviceId)?.cancel();
        liveStates.remove(deviceId);
        liveForecasts.remove(deviceId);
        errors.remove(deviceId);
      }

      Future<void> cancelAllRealtime() async {
        final ids = {...stateSubs.keys, ...forecastSubs.keys}.toList();
        for (final id in ids) {
          await cancelRealtimeFor(id);
        }
      }

      void emitDevices() {
        if (closed) return;
        final devices = userDevices.entries
            .map(
              (entry) => mapTelemetryDevice(
                deviceId: entry.key,
                metadata: entry.value,
                now: DateTime.now(),
                loading: !liveStates.containsKey(entry.key) &&
                    !errors.containsKey(entry.key),
                error: errors[entry.key],
                state: liveStates[entry.key],
                forecast: liveForecasts[entry.key],
              ),
            )
            .toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        controller.add(devices);
      }

      void attachRealtime(String deviceId) {
        if (!stateSubs.containsKey(deviceId)) {
          final stateRef = _database.ref('devices/$deviceId/state');
          stateSubs[deviceId] = stateRef.onValue.listen(
            (event) {
              errors.remove(deviceId);
              liveStates[deviceId] = _asMap(event.snapshot.value);
              emitDevices();
            },
            onError: (_) {
              errors[deviceId] = 'Live telemetry unavailable';
              emitDevices();
            },
          );
        }

        if (!forecastSubs.containsKey(deviceId)) {
          final forecastRef = _database.ref('devices/$deviceId/forecast');
          forecastSubs[deviceId] = forecastRef.onValue.listen(
            (event) {
              liveForecasts[deviceId] = _asMap(event.snapshot.value);
              emitDevices();
            },
            onError: (_) {
              errors[deviceId] = 'Forecast unavailable';
              emitDevices();
            },
          );
        }
      }

      authSub = _auth.authStateChanges().listen((user) async {
        await userDevicesSub?.cancel();
        userDevicesSub = null;

        userDevices.clear();
        await cancelAllRealtime();

        if (closed || _auth.currentUser?.uid != user?.uid) return;
        if (user == null || user.isAnonymous) {
          controller.add(<Device>[]);
          return;
        }

        userDevicesSub = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('devices')
            .snapshots()
            .listen((snapshot) async {
          final nextIds = snapshot.docs.map((doc) => doc.id).toSet();
          final existingIds = userDevices.keys.toSet();

          for (final removedId in existingIds.difference(nextIds)) {
            userDevices.remove(removedId);
            await cancelRealtimeFor(removedId);
          }

          for (final doc in snapshot.docs) {
            userDevices[doc.id] = doc.data();
            attachRealtime(doc.id);
          }

          emitDevices();
        }, onError: controller.addError);
      }, onError: controller.addError);

      freshnessTimer =
          Timer.periodic(const Duration(seconds: 10), (_) => emitDevices());
      controller.onCancel = () async {
        closed = true;
        freshnessTimer?.cancel();
        await authSub?.cancel();
        await userDevicesSub?.cancel();
        await cancelAllRealtime();
      };
    });
  }

  @override
  Future<void> updateControls({
    required String deviceId,
    required bool manual,
    required int fanLevel,
    required bool mist,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final mode = manual ? 'MANUAL' : 'AUTO';

    final membership = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .get();
    if (user.isAnonymous || membership.data()?['role'] != 'owner') {
      throw const DeviceApiException('owner_required', 403);
    }
    await _database.ref('devices/$deviceId/controls').set({
      'mode': mode,
      'fan_level': fanLevel,
      'mist': mist,
      'updated_at': ServerValue.timestamp,
    });
  }

  @override
  Future<bool> validateDeviceId(String deviceId) async {
    final result = await _api.request(
        'POST', '/api/devices/${Uri.encodeComponent(deviceId)}/validate');
    return result['claimable'] == true;
  }

  @override
  Future<void> addDevice(
      {required String deviceId, required String name}) async {
    await _api.request('POST',
        '/api/devices/${Uri.encodeComponent(deviceId)}/claim', {'name': name});
  }

  @override
  Future<void> addDeviceWithPairingCode(
      {required String pairingCode, required String name}) async {
    await _api.request('POST', '/api/pairing/redeem',
        {'code': pairingCode.trim().toUpperCase(), 'name': name});
  }

  @override
  Future<String> createPairingCode({required String deviceId}) async {
    final result = await _api.request(
        'POST', '/api/devices/${Uri.encodeComponent(deviceId)}/pairing');
    return result['code'] as String;
  }

  @override
  Future<void> renameDevice(
      {required String deviceId, required String name}) async {
    await _api.request('PATCH', '/api/devices/${Uri.encodeComponent(deviceId)}',
        {'name': name});
  }

  @override
  Future<void> removeDevice({required String deviceId}) async {
    await _api.request(
        'DELETE', '/api/devices/${Uri.encodeComponent(deviceId)}');
  }

  Future<List<Map<String, dynamic>>> listMembers(String deviceId) async {
    final result = await _api.request(
        'GET', '/api/devices/${Uri.encodeComponent(deviceId)}/members');
    return (result['members'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> revokeMember(String deviceId, String uid) async {
    await _api.request('DELETE',
        '/api/devices/${Uri.encodeComponent(deviceId)}/members/${Uri.encodeComponent(uid)}');
  }

  Stream<List<TelemetryReading>> watchHistory(String deviceId) => _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('history')
          .orderBy('timestamp', descending: true)
          .limit(60)
          .snapshots()
          .map((snapshot) {
        final readings = snapshot.docs
            .map((doc) => TelemetryReading.parse(doc.data()))
            .whereType<TelemetryReading>()
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return readings;
      });

  Map<String, dynamic> _asMap(dynamic value) {
    return value is Map
        ? value.map((key, val) => MapEntry(key.toString(), val))
        : <String, dynamic>{};
  }
}
