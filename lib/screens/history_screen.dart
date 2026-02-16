import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_state.dart';
import '../utils/aqi_utils.dart';
import '../widgets/fade_slide.dart';
import '../widgets/history_chart.dart';
import '../widgets/section_header.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    if (device == null) {
      return const Center(child: Text('No device selected.'));
    }

    final historyAsync = ref.watch(selectedDeviceHistoryProvider);
    final snapshot = device.snapshot;

    return historyAsync.when(
      data: (history) {
        final aqiSeries =
            _series(history, 'aqi', fallback: snapshot.aqi.toDouble());
        final pm25Series = _series(
          history,
          'pm25',
          fallback: snapshot.pm25Avg.toDouble(),
        );
        final pm10Series = _series(history, 'pm10', fallback: 0);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(
              title: 'History',
              subtitle: 'Recent sensor history',
            ),
            FadeSlide(
              child: HistoryChart(
                label: 'AQI',
                points: aqiSeries,
                color: aqiColor(snapshot.aqi),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlide(
              delay: const Duration(milliseconds: 120),
              child: HistoryChart(
                label: 'PM2.5',
                points: pm25Series,
                color: Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 12),
            FadeSlide(
              delay: const Duration(milliseconds: 200),
              child: HistoryChart(
                label: 'PM10',
                points: pm10Series,
                color: Colors.tealAccent,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'History unavailable: $error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  List<double> _series(
    List<Map<String, double>> history,
    String key, {
    required double fallback,
  }) {
    if (history.isEmpty) {
      return List<double>.filled(7, fallback);
    }

    final values = history.map((row) => row[key]).whereType<double>().toList();
    if (values.isEmpty) {
      return List<double>.filled(7, fallback);
    }

    return values;
  }
}
