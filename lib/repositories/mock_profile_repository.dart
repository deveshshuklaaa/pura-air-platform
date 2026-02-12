import 'dart:async';

import '../models/user_profile.dart';
import 'profile_repository.dart';

class MockProfileRepository implements ProfileRepository {
  final _controller = StreamController<UserProfile>.broadcast();
  UserProfile _profile = UserProfile.empty();

  MockProfileRepository() {
    _controller.add(_profile);
  }

  @override
  Stream<UserProfile> watchProfile() => _controller.stream;

  @override
  Future<void> saveProfile(UserProfile profile) async {
    _profile = profile;
    _controller.add(_profile);
  }
}
