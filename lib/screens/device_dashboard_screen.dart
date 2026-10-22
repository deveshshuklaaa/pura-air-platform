import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/device_state.dart';
import '../widgets/aqi_indicator.dart';
import '../widgets/history_chart.dart';
import '../widgets/section_header.dart';

String measurementLabel(num? value, String unit) {
  if (value == null) return 'Unavailable';
  final text = value.toString().replaceFirst(RegExp(r'\.0$'), '');
  return unit.isEmpty ? text : '$text $unit';
}

class DeviceDashboardScreen extends ConsumerWidget {
  const DeviceDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    if (device == null) return const Center(child: Text('No device selected.'));
    final s = device.snapshot;
    final history = ref.watch(selectedDeviceHistoryProvider);
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (s.isTestData)
        const Text('SIMULATED TEST DATA', key: Key('test-data-label')),
      if (s.loading) const LinearProgressIndicator(),
      if (s.error != null) Text('Telemetry error: ${s.error}'),
      if (!s.loading && s.measuredAt == null)
        const Text('Telemetry unavailable'),
      if (s.measuredAt != null && !device.online)
        const Text('Stale / offline — last measurements are not current'),
      if (s.measuredAt != null)
        Text('Measured: ${s.measuredAt!.toLocal().toIso8601String()}'),
      if (s.receivedAt != null)
        Text('Received: ${s.receivedAt!.toLocal().toIso8601String()}'),
      AQIIndicator(snapshot: s),
      const SectionHeader(title: 'Sensor measurements'),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _MetricCard(
            label: 'CO₂', value: measurementLabel(s.co2, 'ppm'), metric: 'co2'),
        _MetricCard(
            label: 'PM2.5',
            value: measurementLabel(s.pm25Avg, 'µg/m³'),
            metric: 'pm25'),
        _MetricCard(
            label: 'PM10',
            value: measurementLabel(s.pm10, 'µg/m³'),
            metric: 'pm10'),
        _MetricCard(
            label: 'Gas index (prototype)',
            value: measurementLabel(s.gasIndex, ''),
            metric: 'gas'),
        _MetricCard(
            label: 'Humidity',
            value: measurementLabel(s.humidity, '%'),
            metric: 'humidity'),
        _MetricCard(
            label: 'Temperature',
            value: measurementLabel(s.temperature, '°C'),
            metric: 'temperature'),
      ]),
      const SectionHeader(title: 'Prototype forecast'),
      const Text('Forecast horizons start at the measurement time.'),
      Text('10-minute prototype forecast: ${s.forecast10 ?? 'Unavailable'}',
          key: const Key('forecast-10')),
      Text('30-minute prototype forecast: ${s.forecast30 ?? 'Unavailable'}',
          key: const Key('forecast-30')),
      if (s.forecastAt != null)
        Text(
            'Forecast calculated: ${s.forecastAt!.toLocal().toIso8601String()}'),
      if (s.forecastAt != null &&
          DateTime.now().difference(s.forecastAt!) > const Duration(minutes: 2))
        const Text('Forecast stale'),
      if (s.forecast10 == null)
        const Text(
            'Forecast requires at least two distinct measurement times.'),
      const SectionHeader(title: 'Measured PM2.5 history'),
      history.when(
          data: (rows) => rows.isEmpty
              ? const Text('No measured history yet.')
              : HistoryChart(
                  label: 'PM2.5 (µg/m³)',
                  points: rows,
                  metric: 'pm25',
                  color: Colors.orangeAccent),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text(
              'History unavailable — check your connection or access.')),
    ]);
  }
}

class _MetricCard extends StatelessWidget {
  final String label, value, metric;
  const _MetricCard(
      {required this.label, required this.value, required this.metric});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: (MediaQuery.sizeOf(context).width - 48) / 2,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(value,
                        key: Key('metric-$metric'),
                        style: Theme.of(context).textTheme.titleMedium)
                  ]))));
}
