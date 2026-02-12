import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import 'profile_repository.dart';

class FirestoreProfileRepository implements ProfileRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirestoreProfileRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<UserProfile> watchProfile() async* {
    yield* _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(UserProfile.empty());
      return _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((doc) => UserProfile.fromMap(doc.data()));
    });
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set(profile.toMap(), SetOptions(merge: true));
  }


}
