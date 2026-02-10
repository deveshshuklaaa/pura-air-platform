import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_state.dart';
import '../utils/aqi_utils.dart';
import '../widgets/aqi_indicator.dart';
import '../widgets/fade_slide.dart';
import '../widgets/section_header.dart';
import '../widgets/trend_graph.dart';

class DeviceDashboardScreen extends ConsumerWidget {
  const DeviceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    if (device == null) {
      return const Center(child: Text('No device selected.'));
    }

    final snapshot = device.snapshot;
    final color = aqiColor(snapshot.aqi);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 4),
        FadeSlide(child: AQIIndicator(snapshot: snapshot)),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Live Metrics'),
        FadeSlide(
          delay: const Duration(milliseconds: 120),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(label: 'CO2', value: '${snapshot.co2} ppm'),
              _MetricCard(label: 'PM2.5', value: '${snapshot.pm25Avg} ug/m3'),
              _MetricCard(label: 'Gas Index', value: snapshot.gasIndex.toStringAsFixed(1)),
              _MetricCard(
                label: 'Humidity',
                value: '${snapshot.humidity.toStringAsFixed(1)}%',
              ),
              _MetricCard(
                label: 'Temp',
                value: '${snapshot.temperature.toStringAsFixed(1)} C',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionHeader(
          title: '15-min Trend',
          subtitle: 'AQI ${trendLabel(snapshot.aqiTrend)}',
        ),
        FadeSlide(
          delay: const Duration(milliseconds: 200),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TrendGraph(
                points: _fakeTrend(snapshot.aqi.toDouble()),
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<double> _fakeTrend(double base) {
    return [
      base - 10,
      base - 6,
      base - 8,
      base - 4,
      base - 2,
      base + 2,
      base + 5,
    ];
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 48) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
