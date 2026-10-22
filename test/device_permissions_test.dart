import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pura_air/models/device.dart';
import 'package:pura_air/models/device_snapshot.dart';
import 'package:pura_air/repositories/device_repository.dart';
import 'package:pura_air/screens/control_panel_screen.dart';
import 'package:pura_air/screens/device_list_screen.dart';
import 'package:pura_air/services/device_api_client.dart';
import 'package:pura_air/state/device_state.dart';

Device device(String role) => Device(
    deviceId: 'PA-TEST',
    name: 'Permission test',
    online: false,
    role: role,
    lastSeen: DateTime(2026),
    snapshot: const DeviceSnapshot(
        co2: 0,
        pm25Avg: 0,
        aqi: 0,
        aqiCategory: 'Unavailable',
        aqiTrend: 0,
        gasIndex: 0,
        fanLevel: 1,
        mist: false,
        mode: 'AUTO',
        humidity: 0,
        temperature: 0));

Widget harness(Widget child, Device selected, DeviceRepository repo) =>
    ProviderScope(overrides: [
      selectedDeviceProvider.overrideWithValue(selected),
      devicesStreamProvider.overrideWith((ref) => Stream.value([selected])),
      deviceRepositoryProvider.overrideWithValue(repo),
    ], child: MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('shared user has no actuator controls', (tester) async {
    await tester.pumpWidget(harness(
        const ControlPanelScreen(), device('shared'), _RejectingRepository()));
    expect(find.textContaining('Shared access is read-only'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });
  testWidgets(
      'owner control rejection shows error and restores reported values',
      (tester) async {
    final repo = _RejectingRepository();
    await tester
        .pumpWidget(harness(const ControlPanelScreen(), device('owner'), repo));
    await tester.tap(find.text('Manual Mode'));
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(find.textContaining('Control request was rejected'), findsOneWidget);
    expect(find.text('Auto logic active'), findsOneWidget);
  });
  testWidgets(
      'shared membership hides owner actions and rejected removal never shows success',
      (tester) async {
    await tester.pumpWidget(harness(
        const DeviceListScreen(), device('shared'), _RejectingRepository()));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Permission test'));
    await tester.pumpAndSettle();
    expect(find.text('Generate Pairing Code'), findsNothing);
    expect(find.text('Rename'), findsNothing);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Device removed'), findsNothing);
    expect(find.textContaining('Only the device owner can do this.'),
        findsOneWidget);
  });
}

class _RejectingRepository implements DeviceRepository {
  int calls = 0;
  @override
  Future<void> updateControls(
      {required String deviceId,
      required bool manual,
      required int fanLevel,
      required bool mist}) async {
    calls++;
    throw const DeviceApiException('owner_required', 403);
  }

  @override
  Future<void> removeDevice({required String deviceId}) async =>
      throw const DeviceApiException('owner_required', 403);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository call');
}
