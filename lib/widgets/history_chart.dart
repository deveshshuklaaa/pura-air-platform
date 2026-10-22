import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/telemetry_reading.dart';

class HistoryChart extends StatelessWidget {
  final String label, metric;
  final List<TelemetryReading> points;
  final Color color;
  const HistoryChart(
      {super.key,
      required this.label,
      required this.points,
      required this.metric,
      required this.color});
  double? value(TelemetryReading r) => switch (metric) {
        'pm25' => r.pm25,
        'pm10' => r.pm10,
        _ => r.indicator?.toDouble()
      };
  @override
  Widget build(BuildContext context) {
    final measured = points.where((r) => value(r) != null).toList();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              if (measured.isEmpty)
                const Text('No measured values for this series.')
              else ...[
                Text(
                    '${measured.first.timestamp.toLocal().toIso8601String()} → ${measured.last.timestamp.toLocal().toIso8601String()}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                AspectRatio(
                    aspectRatio: 2.6,
                    child: LineChart(LineChartData(
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                            spots: [
                              for (final r in measured)
                                FlSpot(
                                    r.timestamp.millisecondsSinceEpoch / 60000,
                                    value(r)!)
                            ],
                            isCurved: false,
                            color: color,
                            barWidth: 3,
                            dotData: const FlDotData(show: true))
                      ],
                    ))),
              ],
            ])));
  }
}
