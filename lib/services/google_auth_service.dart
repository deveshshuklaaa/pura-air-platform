import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  GoogleAuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  Future<UserCredential> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw StateError('Sign in aborted');
    }
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }
}
