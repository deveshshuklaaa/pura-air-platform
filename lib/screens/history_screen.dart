import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/device_state.dart';
import '../widgets/history_chart.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(selectedDeviceProvider) == null) {
      return const Center(child: Text('No device selected.'));
    }
    return ref.watch(selectedDeviceHistoryProvider).when(
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('No measured history yet.'));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('History', style: Theme.of(context).textTheme.titleLarge),
            if (rows.any((r) => r.isTestData))
              const Text('SIMULATED TEST DATA'),
            HistoryChart(
                label: 'PURA particulate indicator (prototype)',
                points: rows,
                metric: 'indicator',
                color: Colors.blueAccent),
            HistoryChart(
                label: 'PM2.5 (µg/m³)',
                points: rows,
                metric: 'pm25',
                color: Colors.orangeAccent),
            HistoryChart(
                label: 'PM10 (µg/m³)',
                points: rows,
                metric: 'pm10',
                color: Colors.tealAccent),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
            child: Text(
                'History unavailable — check your connection or access.')));
  }
}
