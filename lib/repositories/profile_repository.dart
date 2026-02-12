import '../models/user_profile.dart';

abstract class ProfileRepository {
  Stream<UserProfile> watchProfile();
  Future<void> saveProfile(UserProfile profile);
}
