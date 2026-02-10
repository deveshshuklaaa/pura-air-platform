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
    await _ensureSignedIn();
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
    await _ensureSignedIn();
    final user = _auth.currentUser;
    if (user == null) return;
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
    final doc = await _firestore.collection('devices').doc(deviceId).get();
    return doc.exists;
  }

  @override
  Future<void> addDevice({required String deviceId, required String name}) async {
    await _ensureSignedIn();
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .set({
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
    }, SetOptions(merge: true));
  }

  @override
  Future<void> addDeviceWithPairingCode({
    required String pairingCode,
    required String name,
  }) async {
    await _ensureSignedIn();
    final codeDoc = await _firestore.collection('pairing_codes').doc(pairingCode).get();
    if (!codeDoc.exists) {
      throw StateError('Pairing code not found');
    }
    final data = codeDoc.data() ?? <String, dynamic>{};
    final deviceId = (data['device_id'] ?? data['deviceId']) as String?;
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Invalid pairing code');
    }
    await addDevice(deviceId: deviceId, name: name);
    await codeDoc.reference.delete();
  }

  @override
  Future<void> renameDevice({required String deviceId, required String name}) async {
    await _ensureSignedIn();
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .set({'name': name}, SetOptions(merge: true));
  }

  @override
  Future<void> removeDevice({required String deviceId}) async {
    await _ensureSignedIn();
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .delete();
  }

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
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
