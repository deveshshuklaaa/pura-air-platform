import 'package:flutter/material.dart';

import '../widgets/section_header.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _aqiWarnings = true;
  bool _failsafe = true;
  bool _offlineAlerts = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'Notifications',
          subtitle: 'Never spam, only the essentials',
        ),
        SwitchListTile.adaptive(
          value: _aqiWarnings,
          onChanged: (value) => setState(() => _aqiWarnings = value),
          title: const Text('AQI warnings'),
          subtitle: const Text('Alert when AQI crosses limits'),
        ),
        SwitchListTile.adaptive(
          value: _failsafe,
          onChanged: (value) => setState(() => _failsafe = value),
          title: const Text('Failsafe notifications'),
          subtitle: const Text('Device safety and error notices'),
        ),
        SwitchListTile.adaptive(
          value: _offlineAlerts,
          onChanged: (value) => setState(() => _offlineAlerts = value),
          title: const Text('Offline alerts'),
          subtitle: const Text('Notify when device is offline'),
        ),
      ],
    );
  }
}
