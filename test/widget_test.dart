import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pura_air/main.dart';
import 'package:pura_air/state/auth_state.dart';

void main() {
  testWidgets('Signed-out app presents the sign-in form without Firebase',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(ProviderScope(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      authControllerProvider.overrideWithValue(_UnusedAuthController()),
    ], child: const PuraAirApp()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('App boots into an isolated authentication error screen',
      (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) =>
            Stream<User?>.error(StateError('Test authentication unavailable')))
      ],
      child: const PuraAirApp(),
    ));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(
        find.textContaining(
            'Auth error: Bad state: Test authentication unavailable'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _UnusedAuthController implements AuthController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No sign-in call expected');
}
