import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../state/auth_state.dart';
import 'auth_screen.dart';
import '../state/profile_state.dart';
import '../widgets/auth_required_view.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _aboutController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authStateProvider, (previous, next) {
      next.whenData((user) {
        if (user != null || !mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      });
    });
    ref.listenManual(profileStreamProvider, (previous, next) {
      next.whenData((profile) {
        if (_initialized) return;
        _applyProfile(profile);
        _initialized = true;
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileStreamProvider);
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Guest';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: profileAsync.when(
        data: (_) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        user?.uid ?? 'Anonymous',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aboutController,
              decoration: const InputDecoration(labelText: 'About'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final profile = UserProfile(
                          displayName: _nameController.text.trim(),
                          phone: _phoneController.text.trim(),
                          location: _locationController.text.trim(),
                          about: _aboutController.text.trim(),
                        );
                        await ref.read(profileRepositoryProvider).saveProfile(profile);
                        if (!mounted) return;
                        setState(() => _saving = false);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Profile saved')),
                        );
                      },
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => ref.read(authControllerProvider).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          if (err is FirebaseException && err.code == 'permission-denied') {
            return const AuthRequiredView(
              message: 'Please sign in to view your profile.',
            );
          }
          return Center(child: Text('Error: $err'));
        },
      ),
    );
  }

  void _applyProfile(UserProfile profile) {
    _nameController.text = profile.displayName;
    _phoneController.text = profile.phone;
    _locationController.text = profile.location;
    _aboutController.text = profile.about;
  }
}
