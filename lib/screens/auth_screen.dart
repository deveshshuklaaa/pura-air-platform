import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/google_auth_service.dart';
import '../state/auth_state.dart';
import '../state/theme_state.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authControllerProvider);
    final googleAuth = GoogleAuthService();
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0A0D12), Color(0xFF101826)]
                : const [Color(0xFFF4F7FB), Color(0xFFE6ECF5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isRegister ? 'Create account' : 'Welcome back',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to sync devices',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                          ),
                          const SizedBox(height: 20),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(labelText: 'Email'),
                                  validator: (value) => value != null && value.contains('@')
                                      ? null
                                      : 'Enter a valid email',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  decoration: const InputDecoration(labelText: 'Password'),
                                  validator: (value) => value != null && value.length >= 6
                                      ? null
                                      : 'Min 6 characters',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _loading
                                  ? null
                                  : () async {
                                      if (!_formKey.currentState!.validate()) return;
                                      setState(() {
                                        _loading = true;
                                        _error = null;
                                      });
                                      try {
                                        if (_isRegister) {
                                          await auth.registerWithEmail(
                                            _emailController.text.trim(),
                                            _passwordController.text.trim(),
                                          );
                                        } else {
                                          await auth.signInWithEmail(
                                            _emailController.text.trim(),
                                            _passwordController.text.trim(),
                                          );
                                        }
                                      } on Exception catch (e) {
                                        setState(() => _error = e.toString());
                                      } finally {
                                        if (mounted) setState(() => _loading = false);
                                      }
                                    },
                              child: Text(_isRegister ? 'Create account' : 'Sign in'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () async {
                                      setState(() {
                                        _loading = true;
                                        _error = null;
                                      });
                                      try {
                                        await googleAuth.signInWithGoogle();
                                      } on Exception catch (e) {
                                        setState(() => _error = e.toString());
                                      } finally {
                                        if (mounted) setState(() => _loading = false);
                                      }
                                    },
                              icon: const Icon(Icons.g_mobiledata),
                              label: const Text('Continue with Google'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () async {
                                    setState(() {
                                      _loading = true;
                                      _error = null;
                                    });
                                    try {
                                      await auth.signInAnonymously();
                                    } on Exception catch (e) {
                                      setState(() => _error = e.toString());
                                    } finally {
                                      if (mounted) setState(() => _loading = false);
                                    }
                                  },
                            child: const Text('Continue as guest'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_isRegister
                                  ? 'Already have an account?'
                                  : 'New here?'),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => setState(() => _isRegister = !_isRegister),
                                child: Text(_isRegister ? 'Sign in' : 'Create one'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () {
                    ref.read(themeModeProvider.notifier).state =
                        themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
