import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(FirebaseAuth.instance);
});

class AuthController {
  AuthController(this._auth);
  final FirebaseAuth _auth;

  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmail(String email, String password) {
    return _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signInAnonymously() {
    return _auth.signInAnonymously();
  }

  Future<void> signOut() {
    return _auth.signOut();
  }
}
