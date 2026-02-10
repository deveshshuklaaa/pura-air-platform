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
    final snapshot = device.snapshot;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'History',
          subtitle: 'Past 24 hours',
        ),
        FadeSlide(
          child: HistoryChart(
            label: 'AQI',
            points: _historySeries(snapshot.aqi.toDouble()),
            color: aqiColor(snapshot.aqi),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlide(
          delay: const Duration(milliseconds: 120),
          child: HistoryChart(
            label: 'CO2',
            points: _historySeries(snapshot.co2.toDouble()),
            color: Colors.tealAccent,
          ),
        ),
        const SizedBox(height: 12),
        FadeSlide(
          delay: const Duration(milliseconds: 200),
          child: HistoryChart(
            label: 'PM2.5',
            points: _historySeries(snapshot.pm25Avg.toDouble()),
            color: Colors.orangeAccent,
          ),
        ),
      ],
    );
  }

  List<double> _historySeries(double base) {
    return [
      base - 14,
      base - 6,
      base - 10,
      base - 4,
      base + 2,
      base + 6,
      base + 4,
    ];
  }
}
