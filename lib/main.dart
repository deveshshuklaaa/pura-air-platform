import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'state/auth_state.dart';
import 'state/theme_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    await NotificationService.initialize();
  } catch (_) {
    // Firebase may be unavailable during initial setup; app will fall back to mock data.
  }
  runApp(const ProviderScope(child: PuraAirApp()));
}

class PuraAirApp extends ConsumerWidget {
  const PuraAirApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'PURA AIR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);
    return authAsync.when(
      data: (user) {
        if (user == null) return const AuthScreen();
        return const HomeShell();
      },
      loading: () => const SplashScreen(),
      error: (err, _) => Scaffold(
        body: Center(child: Text('Auth error: $err')),
      ),
    );
  }
}
