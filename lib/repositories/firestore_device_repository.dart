import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/device.dart';
import '../models/device_snapshot.dart';
import 'device_repository.dart';

class FirestoreDeviceRepository implements DeviceRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;

  FirestoreDeviceRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseDatabase? database,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _database = database ?? FirebaseDatabase.instance;

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

      Future<void> cancelRealtimeFor(String deviceId) async {
        await stateSubs.remove(deviceId)?.cancel();
        await forecastSubs.remove(deviceId)?.cancel();
        liveStates.remove(deviceId);
        liveForecasts.remove(deviceId);
      }

      Future<void> cancelAllRealtime() async {
        final ids = {...stateSubs.keys, ...forecastSubs.keys}.toList();
        for (final id in ids) {
          await cancelRealtimeFor(id);
        }
      }

      void emitDevices() {
        final devices = userDevices.entries
            .map(
              (entry) => _mapDevice(
                deviceId: entry.key,
                data: entry.value,
                liveState: liveStates[entry.key],
                liveForecast: liveForecasts[entry.key],
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
              liveStates[deviceId] = _asMap(event.snapshot.value);
              emitDevices();
            },
            onError: (_) {
              liveStates.remove(deviceId);
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
              liveForecasts.remove(deviceId);
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

        if (user == null) {
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

      controller.onCancel = () async {
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

    await Future.wait([
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId)
          .set({
        'state': {
          'mode': mode,
          'fan_level': fanLevel,
          'mist': mist,
        },
      }, SetOptions(merge: true)),
      _database.ref('devices/$deviceId/controls').set({
        'mode': mode,
        'fan_level': fanLevel,
        'mist': mist,
        'updated_at': ServerValue.timestamp,
      }),
    ]);
  }

  @override
  Future<bool> validateDeviceId(String deviceId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }

    final doc = await _firestore.collection('devices').doc(deviceId).get();
    if (!doc.exists) return false;
    final ownerUid = doc.data()?['owner_uid'] as String?;
    return ownerUid == null || ownerUid == user.uid;
  }

  @override
  Future<void> addDevice(
      {required String deviceId, required String name}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }

    await _firestore.runTransaction((tx) async {
      final deviceRef = _firestore.collection('devices').doc(deviceId);
      final deviceSnap = await tx.get(deviceRef);
      if (!deviceSnap.exists) {
        throw StateError('Device not registered');
      }

      final ownerUid = deviceSnap.data()?['owner_uid'] as String?;
      if (ownerUid != null && ownerUid != user.uid) {
        throw StateError('Device already claimed');
      }

      if (ownerUid == null) {
        tx.update(deviceRef, {'owner_uid': user.uid});
      }

      final userDeviceRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId);
      tx.set(userDeviceRef, _userDevicePayload(name), SetOptions(merge: true));
    });

    await _database.ref('device_access/${user.uid}/$deviceId').set(true);
  }

  @override
  Future<void> addDeviceWithPairingCode({
    required String pairingCode,
    required String name,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }

    await _firestore.runTransaction((tx) async {
      final codeRef = _firestore.collection('pairing_codes').doc(pairingCode);
      final codeSnap = await tx.get(codeRef);
      if (!codeSnap.exists) {
        throw StateError('Pairing code not found');
      }

      final data = codeSnap.data() ?? <String, dynamic>{};
      final deviceId = (data['device_id'] ?? data['deviceId']) as String?;
      final ownerFromCode =
          (data['owner_uid'] ?? data['created_by']) as String?;
      if (deviceId == null || deviceId.isEmpty) {
        throw StateError('Invalid pairing code');
      }

      final deviceRef = _firestore.collection('devices').doc(deviceId);
      final deviceSnap = await tx.get(deviceRef);
      if (!deviceSnap.exists) {
        throw StateError('Device not registered');
      }

      final deviceOwner = deviceSnap.data()?['owner_uid'] as String?;
      if (deviceOwner == null) {
        throw StateError('Device not claimed yet');
      }
      if (ownerFromCode != null && ownerFromCode != deviceOwner) {
        throw StateError('Invalid pairing code');
      }

      final userDeviceRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId);
      tx.set(userDeviceRef, _userDevicePayload(name), SetOptions(merge: true));
      tx.delete(codeRef);

      await _database.ref('device_access/${user.uid}/$deviceId').set(true);
    });
  }

  @override
  Future<String> createPairingCode({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }

    final deviceDoc =
        await _firestore.collection('devices').doc(deviceId).get();
    if (!deviceDoc.exists) {
      throw StateError('Device not registered');
    }
    final ownerUid = deviceDoc.data()?['owner_uid'] as String?;
    if (ownerUid != user.uid) {
      throw StateError('Only the owner can generate pairing codes');
    }

    final codes = _firestore.collection('pairing_codes');
    for (var i = 0; i < 5; i++) {
      final code = _generateCode();
      final doc = codes.doc(code);
      final snap = await doc.get();
      if (snap.exists) continue;
      await doc.set({
        'device_id': deviceId,
        'owner_uid': ownerUid,
        'created_by': user.uid,
        'created_at': FieldValue.serverTimestamp(),
      });
      return code;
    }
    throw StateError('Unable to generate pairing code');
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer('PC-');
    var seed = now;
    for (var i = 0; i < 6; i++) {
      final index = seed % chars.length;
      buffer.write(chars[index]);
      seed = (seed ~/ chars.length) + i;
    }
    return buffer.toString();
  }

  Map<String, dynamic> _userDevicePayload(String name) {
    return {
      'name': name,
      'online': true,
      'last_seen': FieldValue.serverTimestamp(),
      'state': {
        'fan_level': 1,
        'mist': false,
        'mode': 'AUTO',
      },
    };
  }

  @override
  Future<void> renameDevice(
      {required String deviceId, required String name}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .set({'name': name}, SetOptions(merge: true));
  }

  @override
  Future<void> removeDevice({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    await Future.wait([
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId)
          .delete(),
      _database.ref('device_access/${user.uid}/$deviceId').remove(),
    ]);
  }

  Device _mapDevice({
    required String deviceId,
    required Map<String, dynamic> data,
    Map<String, dynamic>? liveState,
    Map<String, dynamic>? liveForecast,
  }) {
    final storedState = _asMap(data['state']);
    final state = {...storedState, ...?liveState};

    final aqi = _asInt(state['aqi'], fallback: 0);
    final forecast10 = _asInt(liveForecast?['aqi_10min'], fallback: aqi);
    final trend = forecast10 - aqi;

    final lastSeenRaw = state['last_updated'] ?? data['last_seen'];
    final lastSeen = _parseLastSeen(lastSeenRaw);

    final onlineFromData = (data['online'] as bool?) ?? true;
    final online = DateTime.now().difference(lastSeen).inMinutes <= 2
        ? true
        : onlineFromData;

    return Device(
      deviceId: deviceId,
      name: (data['name'] as String?) ?? 'PURA AIR',
      online: online,
      lastSeen: lastSeen,
      snapshot: DeviceSnapshot(
        co2: _asInt(state['co2'], fallback: 0),
        pm25Avg: _asInt(state['pm25'] ?? state['pm25_avg'], fallback: 0),
        aqi: aqi,
        aqiCategory: _aqiCategory(aqi),
        aqiTrend: trend,
        gasIndex: _asDouble(state['gas_index'], fallback: 0.0),
        fanLevel: _asInt(storedState['fan_level'], fallback: 1),
        mist: (storedState['mist'] as bool?) ?? false,
        mode: (storedState['mode'] as String?) ?? 'AUTO',
        humidity: _asDouble(state['humidity'], fallback: 0.0),
        temperature: _asDouble(state['temperature'], fallback: 0.0),
      ),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  DateTime _parseLastSeen(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is double) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    return DateTime.now();
  }

  String _aqiCategory(int aqi) {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for Sensitive Groups';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double _asDouble(dynamic value, {required double fallback}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }
}
