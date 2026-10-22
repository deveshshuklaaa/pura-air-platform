import 'package:flutter/material.dart';

import '../models/device.dart';
import '../utils/aqi_utils.dart';

class DeviceCardWidget extends StatelessWidget {
  final Device device;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const DeviceCardWidget({
    super.key,
    required this.device,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = aqiColor(device.snapshot.aqi);
    final online = device.online;

    return AnimatedScale(
      scale: selected ? 1.0 : 0.98,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        online ? 'Online' : 'Offline',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: online
                              ? theme.colorScheme.secondary
                              : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Last seen ${_relativeTime(device.lastSeen)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      device.snapshot.aqi?.toString() ?? 'Unavailable',
                      style:
                          theme.textTheme.headlineSmall?.copyWith(color: color),
                    ),
                    Text(
                      device.snapshot.aqiCategory,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return 'unavailable';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
