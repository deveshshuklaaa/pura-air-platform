import 'package:flutter/material.dart';
import '../models/device_snapshot.dart';
import '../utils/aqi_utils.dart';

class AQIIndicator extends StatelessWidget {
  final DeviceSnapshot snapshot;
  const AQIIndicator({super.key, required this.snapshot});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('PURA particulate indicator (prototype)'),
            Text(snapshot.aqi?.toString() ?? 'Unavailable',
                key: const Key('particulate-indicator'),
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(color: aqiColor(snapshot.aqi))),
            const Text('Instantaneous particulate estimate — not official AQI'),
          ])));
}
