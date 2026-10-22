import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pura_air/models/device.dart';
import 'package:pura_air/models/device_snapshot.dart';
import 'package:pura_air/screens/home_shell.dart';
import 'package:pura_air/state/auth_state.dart';
import 'package:pura_air/state/device_state.dart';

void main() {
  testWidgets(
      'shell handles delayed device and sign-out data without dynamic extension calls',
      (tester) async {
    final devices = StreamController<List<Device>>.broadcast();
    final auth = StreamController<User?>.broadcast();
    final container = ProviderContainer(overrides: [
      useFirebaseProvider.overrideWithValue(false),
      devicesStreamProvider.overrideWith((ref) => devices.stream),
      authStateProvider.overrideWith((ref) => auth.stream),
      authControllerProvider.overrideWithValue(_UnusedAuthController()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeShell())));
    await tester.pump();
    devices.add([
      Device(
        deviceId: 'PA-DELAYED',
        name: 'Delayed telemetry device',
        online: false,
        lastSeen: DateTime(2026),
        snapshot: const DeviceSnapshot(
          co2: null,
          pm25Avg: null,
          aqi: null,
          aqiCategory: 'Unavailable',
          aqiTrend: null,
          gasIndex: null,
          humidity: null,
          temperature: null,
          fanLevel: 1,
          mist: false,
          mode: 'AUTO',
        ),
      )
    ]);
    await tester.pumpAndSettle();
    expect(container.read(selectedDeviceIdProvider), 'PA-DELAYED');
    expect(tester.takeException(), isNull);
    auth.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await devices.close();
    await auth.close();
  });
}

class _UnusedAuthController implements AuthController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No authentication request expected');
}
