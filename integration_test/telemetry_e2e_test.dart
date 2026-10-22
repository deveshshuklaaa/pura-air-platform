import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pura_air/main.dart';
import 'package:pura_air/state/device_state.dart';
import 'package:pura_air/widgets/history_chart.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'physical phone displays exact simulator measurements from isolated Firebase',
      (tester) async {
    if (!const bool.fromEnvironment('PURA_ISOLATED_TEST')) {
      throw StateError('Explicit isolated build required');
    }
    final app = await Firebase.initializeApp();
    if (app.options.projectId != 'demo-pura-security') {
      throw StateError('Production Firebase refused');
    }
    await FirebaseAuth.instance
        .useAuthEmulator('127.0.0.1', 19099, automaticHostMapping: false);
    FirebaseFirestore.instance
        .useFirestoreEmulator('127.0.0.1', 18080, automaticHostMapping: false);
    FirebaseDatabase.instance
        .useDatabaseEmulator('127.0.0.1', 19000, automaticHostMapping: false);
    await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: 'phone-owner@example.test', password: 'LocalOnly-1b-Fixture!');
    final client = HttpClient();
    late Map<String, dynamic> fixture;
    try {
      final req =
          await client.postUrl(Uri.parse('http://127.0.0.1:18088/fixture/run'));
      final response = await req.close();
      expect(response.statusCode, 200);
      fixture = jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
    GoogleFonts.config.allowRuntimeFetching = false;
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const PuraAirApp()));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (container.read(selectedDeviceProvider)?.snapshot.eventId !=
        (fixture['state'] as Map)['event_id']) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Live repository did not receive the fixture');
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
    final device = container.read(selectedDeviceProvider)!;
    expect(device.snapshot.pm25Avg, 19.6);
    expect(device.snapshot.pm10, 45);
    expect(device.snapshot.co2, 460);
    expect(device.online, true);
    expect(device.snapshot.isTestData, true);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('metric-pm25'))).data,
        '19.6 µg/m³');
    expect(tester.widget<Text>(find.byKey(const Key('metric-pm10'))).data,
        '45 µg/m³');
    expect(tester.widget<Text>(find.byKey(const Key('metric-co2'))).data,
        '460 ppm');
    expect(find.text('SIMULATED TEST DATA'), findsWidgets);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    final rows = container.read(selectedDeviceHistoryProvider).asData?.value;
    expect(rows, isNotNull);
    expect(rows!.map((r) => r.pm25).toList(), [14.6, 17.1, 19.6]);
    expect(rows.map((r) => r.eventId).toSet().length, 3);
    final chart =
        tester.widgetList<HistoryChart>(find.byType(HistoryChart)).first;
    expect(chart.points.length, 3);
    // Logs contain only synthetic fixture values, never authentication tokens.
    debugPrint(
        'PURA_PHYSICAL_E2E_PASS pm25=19.6 pm10=45 co2=460 history=3 source=simulator');
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await FirebaseAuth.instance.signOut();
  });
}
