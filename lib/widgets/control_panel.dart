import 'package:flutter/material.dart';

class ControlPanel extends StatelessWidget {
  final String mode;
  final int fanLevel;
  final bool mist;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<double> onFanChanged;
  final ValueChanged<double>? onFanChangeEnd;
  final ValueChanged<bool> onMistChanged;

  const ControlPanel({
    super.key,
    required this.mode,
    required this.fanLevel,
    required this.mist,
    required this.onModeChanged,
    required this.onFanChanged,
    this.onFanChangeEnd,
    required this.onMistChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isManual = mode == 'MANUAL';
    return Column(
      children: [
        SwitchListTile.adaptive(
          value: isManual,
          onChanged: onModeChanged,
          title: const Text('Manual Mode'),
          subtitle: Text(isManual ? 'Auto logic paused' : 'Auto logic active'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fan Speed',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Slider(
                  min: 1,
                  max: 5,
                  divisions: 4,
                  value: fanLevel.toDouble(),
                  onChanged: onFanChanged,
                  onChangeEnd: onFanChangeEnd,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('Level $fanLevel'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          value: mist,
          onChanged: onMistChanged,
          title: const Text('Mist'),
          subtitle: const Text('Humidity boost'),
        ),
        if (isManual)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Manual mode is active. Auto adjustments are paused.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orangeAccent,
                  ),
            ),
          ),
      ],
    );
  }
}
