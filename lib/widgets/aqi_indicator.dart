import 'package:flutter/material.dart';

import '../models/device_snapshot.dart';
import '../utils/aqi_utils.dart';

class AQIIndicator extends StatelessWidget {
  final DeviceSnapshot snapshot;

  const AQIIndicator({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final color = aqiColor(snapshot.aqi);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AQI',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        letterSpacing: 1.6,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.aqi}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  snapshot.aqiCategory,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trendLabel(snapshot.aqiTrend),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
              const SizedBox(height: 8),
              Icon(
                snapshot.aqiTrend >= 0 ? Icons.trending_up : Icons.trending_down,
                color: color,
                size: 28,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
