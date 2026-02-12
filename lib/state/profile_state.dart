import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../repositories/firestore_profile_repository.dart';
import '../repositories/mock_profile_repository.dart';
import '../repositories/profile_repository.dart';
import 'device_state.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirestoreProfileRepository() : MockProfileRepository();
});

final profileStreamProvider = StreamProvider<UserProfile>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return repo.watchProfile();
});
