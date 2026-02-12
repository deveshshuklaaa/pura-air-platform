import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_state.dart';
import '../state/profile_state.dart';
import '../state/theme_state.dart';
import '../state/auth_state.dart';
import 'control_panel_screen.dart';
import 'device_dashboard_screen.dart';
import 'device_list_screen.dart';
import 'history_screen.dart';
import 'notifications_screen.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final ProviderSubscription _deviceListener;
  late final ProviderSubscription _authListener;

  @override
  void initState() {
    super.initState();
    _authListener = ref.listenManual(authStateProvider, (previous, next) {
      next.whenData((user) {
        ref.invalidate(devicesStreamProvider);
        ref.invalidate(profileStreamProvider);
        ref.invalidate(selectedDeviceIdProvider);
        if (user == null && mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
          );
        }
      });
    });
    _deviceListener = ref.listenManual(devicesStreamProvider, (previous, next) {
      next.whenData((devices) {
        if (devices.isEmpty) return;
        final selected = ref.read(selectedDeviceIdProvider);
        if (selected == null) {
          ref.read(selectedDeviceIdProvider.notifier).state = devices.first.deviceId;
        }
      });
    });
  }

  @override
  void dispose() {
    _deviceListener.close();
    _authListener.close();
    super.dispose();
  }

  int _index = 0;

  final _screens = const [
    DeviceListScreen(),
    DeviceDashboardScreen(),
    ControlPanelScreen(),
    HistoryScreen(),
    NotificationsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(selectedDeviceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(device?.name ?? 'PURA AIR'),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          if (device != null)
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              child: Chip(
                label: Text(device.online ? 'Online' : 'Offline'),
                backgroundColor: device.online
                    ? Colors.greenAccent.withValues(alpha: 0.15)
                    : Colors.redAccent.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: device.online ? Colors.greenAccent : Colors.redAccent,
                ),
                side: BorderSide(
                  color: device.online ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0A0D12), Color(0xFF111827)]
                : const [Color(0xFFF4F7FB), Color(0xFFE6ECF5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _screens[_index],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.devices_other_outlined),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            label: 'Control',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}
