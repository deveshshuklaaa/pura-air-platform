import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/device.dart';
import '../models/device_snapshot.dart';
import 'device_repository.dart';

class FirestoreDeviceRepository implements DeviceRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirestoreDeviceRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<List<Device>> watchDevices() async* {
    yield* _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(<Device>[]);
      return _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .snapshots()
          .map(_mapSnapshot);
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
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .set({
      'state': {
        'mode': manual ? 'MANUAL' : 'AUTO',
        'fan_level': fanLevel,
        'mist': mist,
      },
    }, SetOptions(merge: true));
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
  Future<void> addDevice({required String deviceId, required String name}) async {
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
      final ownerFromCode = (data['owner_uid'] ?? data['created_by']) as String?;
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
    });
  }

  @override
  Future<String> createPairingCode({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }

    final deviceDoc = await _firestore.collection('devices').doc(deviceId).get();
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
        'aqi': 0,
        'aqi_category': 'Unknown',
        'aqi_trend': 0,
        'co2': 0,
        'pm25_avg': 0,
        'gas_index': 0.0,
        'fan_level': 1,
        'mist': false,
        'mode': 'AUTO',
        'humidity': 0.0,
        'temperature': 0.0,
      },
    };
  }

  @override
  Future<void> renameDevice({required String deviceId, required String name}) async {
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
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .delete();
  }

  List<Device> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((doc) => _mapDevice(doc.id, doc.data())).toList();
  }

  Device _mapDevice(String deviceId, Map<String, dynamic> data) {
    final state = (data['state'] as Map<String, dynamic>?) ?? data;
    final lastSeenRaw = data['last_seen'] ?? state['last_seen'];
    final lastSeen = _parseLastSeen(lastSeenRaw);

    return Device(
      deviceId: deviceId,
      name: (data['name'] as String?) ?? 'PURA AIR',
      online: (data['online'] as bool?) ?? true,
      lastSeen: lastSeen,
      snapshot: DeviceSnapshot(
        co2: _asInt(state['co2'], fallback: 0),
        pm25Avg: _asInt(state['pm25_avg'], fallback: 0),
        aqi: _asInt(state['aqi'], fallback: 0),
        aqiCategory: (state['aqi_category'] as String?) ?? 'Unknown',
        aqiTrend: _asInt(state['aqi_trend'], fallback: 0),
        gasIndex: _asDouble(state['gas_index'], fallback: 0.0),
        fanLevel: _asInt(state['fan_level'], fallback: 1),
        mist: (state['mist'] as bool?) ?? false,
        mode: (state['mode'] as String?) ?? 'AUTO',
        humidity: _asDouble(state['humidity'], fallback: 0.0),
        temperature: _asDouble(state['temperature'], fallback: 0.0),
      ),
    );
  }

  DateTime _parseLastSeen(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    if (raw is double) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    return DateTime.now();
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
