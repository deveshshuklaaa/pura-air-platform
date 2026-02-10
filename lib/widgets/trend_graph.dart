import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class TrendGraph extends StatelessWidget {
  final List<double> points;
  final Color color;

  const TrendGraph({super.key, required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.4,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            LineChartBarData(
              dashArray: [6, 4],
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i]),
              ],
              isCurved: true,
              color: color,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
