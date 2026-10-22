import 'dart:convert';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pura_air/models/device.dart';
import 'package:pura_air/models/telemetry_reading.dart';
import 'package:pura_air/screens/device_dashboard_screen.dart';
import 'package:pura_air/screens/history_screen.dart';
import 'package:pura_air/state/device_state.dart';
import 'package:pura_air/widgets/history_chart.dart';

void main() {
  final fixture = jsonDecode(
      File('docs/development/artifacts/telemetry-fixture.json')
          .readAsStringSync()) as Map<String, dynamic>;
  final state = Map<String, dynamic>.from(fixture['state'] as Map);
  final forecast = Map<String, dynamic>.from(fixture['forecast'] as Map);
  final now = telemetryTime(state['server_received_at'])!
      .add(const Duration(seconds: 1));
  Device map(
          {Map<String, dynamic>? raw,
          DateTime? at,
          String? error,
          bool loading = false}) =>
      mapTelemetryDevice(
          deviceId: 'PA-SIM',
          metadata: {'name': 'Fixture', 'role': 'owner', 'online': true},
          state: raw ?? state,
          forecast: forecast,
          now: at ?? now,
          error: error,
          loading: loading);
  final rows = (fixture['history'] as List)
      .map((r) => TelemetryReading.parse(Map<String, dynamic>.from(r as Map))!)
      .toList();
  Widget harness(Widget screen, Device device,
          {Stream<List<TelemetryReading>>? history}) =>
      ProviderScope(overrides: [
        selectedDeviceProvider.overrideWithValue(device),
        selectedDeviceHistoryProvider
            .overrideWith((ref) => history ?? Stream.value(rows)),
      ], child: MaterialApp(home: Scaffold(body: screen)));

  test('maps the exact measurements actually persisted by the emulator suite',
      () {
    final device = map();
    expect(device.snapshot.pm25Avg, 19.6);
    expect(device.snapshot.pm10, 45);
    expect(device.snapshot.co2, 460);
    expect(device.snapshot.humidity, 48);
    expect(device.snapshot.temperature, 23.6);
    expect(device.snapshot.isTestData, true);
    expect(device.snapshot.aqi, state['particulate_indicator']);
    expect(device.snapshot.forecast10, forecast['aqi_10min']);
    expect(device.online, true);
    expect(rows.map((r) => r.pm25), [14.6, 17.1, 19.6]);
  });
  test(
      'missing/malformed measurements and legacy undocumented AQI remain unavailable',
      () {
    final missing = map(raw: {'aqi': 0, 'pm25': false, 'co2': '500'});
    expect(missing.snapshot.aqi, isNull);
    expect(missing.snapshot.pm25Avg, isNull);
    expect(missing.snapshot.co2, isNull);
    expect(missing.online, false);
    expect(TelemetryReading.parse({'timestamp': 'wrong'}), isNull);
    final row =
        TelemetryReading.parse({'timestamp': state['timestamp'], 'pm25': null});
    expect(row!.pm25, isNull);
    expect(row.indicator, isNull);
  });
  test(
      'stored online true cannot override stale measurements or live read errors',
      () {
    expect(map(at: now.add(const Duration(minutes: 3))).online, false);
    expect(map(error: 'Permission denied').online, false);
    expect(map(error: 'Permission denied').snapshot.error, 'Permission denied');
  });
  testWidgets(
      'dashboard displays exact fixture values, test label and real forecast horizons',
      (tester) async {
    await tester.pumpWidget(harness(const DeviceDashboardScreen(), map()));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('metric-pm25'))).data,
        '19.6 µg/m³');
    expect(tester.widget<Text>(find.byKey(const Key('metric-pm10'))).data,
        '45 µg/m³');
    expect(find.text('SIMULATED TEST DATA'), findsOneWidget);
    expect(find.text('15-min Trend'), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('forecast-10')), 200);
    expect(find.text('10-minute prototype forecast: ${forecast['aqi_10min']}'),
        findsOneWidget);
    expect(find.text('30-minute prototype forecast: ${forecast['aqi_30min']}'),
        findsOneWidget);
  });
  testWidgets('empty history has no invented chart samples', (tester) async {
    await tester.pumpWidget(
        harness(const HistoryScreen(), map(), history: Stream.value([])));
    await tester.pumpAndSettle();
    expect(find.text('No measured history yet.'), findsOneWidget);
    expect(find.byType(HistoryChart), findsNothing);
  });
  testWidgets('loading and history error states are distinct', (tester) async {
    await tester.pumpWidget(
        harness(const HistoryScreen(), map(), history: const Stream.empty()));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(harness(const HistoryScreen(), map(),
        history: Stream.error(StateError('offline'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('History unavailable'), findsOneWidget);
  });
  testWidgets(
      'stale and unavailable readings never display Good or zero fallback',
      (tester) async {
    await tester
        .pumpWidget(harness(const DeviceDashboardScreen(), map(raw: {})));
    await tester.pumpAndSettle();
    expect(find.text('Telemetry unavailable'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('particulate-indicator')))
            .data,
        'Unavailable');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(harness(const DeviceDashboardScreen(),
        map(at: now.add(const Duration(minutes: 3)))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stale / offline'), findsOneWidget);
  });
  testWidgets(
      'chart x coordinates are actual measurement timestamps and values are unchanged',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HistoryChart(
                label: 'Fixture',
                points: rows,
                metric: 'pm25',
                color: Colors.blue))));
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.map((p) => p.y),
        [14.6, 17.1, 19.6]);
    expect(chart.data.lineBarsData.single.spots.first.x,
        rows.first.timestamp.millisecondsSinceEpoch / 60000);
  });
}
