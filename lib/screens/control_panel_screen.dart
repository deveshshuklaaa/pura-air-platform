import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_state.dart';
import '../repositories/device_repository.dart';
import '../widgets/control_panel.dart';
import '../widgets/section_header.dart';

class ControlPanelScreen extends ConsumerStatefulWidget {
  const ControlPanelScreen({super.key});

  @override
  ConsumerState<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends ConsumerState<ControlPanelScreen> {
  bool _manual = false;
  int _fanLevel = 2;
  bool _mist = false;
  String? _lastDeviceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFromDevice();
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(selectedDeviceProvider);
    final repo = ref.watch(deviceRepositoryProvider);
    if (device == null) {
      return const Center(child: Text('No device selected.'));
    }
    if (!device.canControl) {
      return const Center(
          child: Text(
              'Shared access is read-only. Only the owner can control this device.'));
    }
    if (device.deviceId != _lastDeviceId) {
      _syncFromDevice();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'Control Panel',
          subtitle: 'Manual controls override auto logic',
        ),
        ControlPanel(
          mode: _manual ? 'MANUAL' : 'AUTO',
          fanLevel: _fanLevel,
          mist: _mist,
          onModeChanged: (value) {
            setState(() => _manual = value);
            _persistControls(repo, device.deviceId);
          },
          onFanChanged: (value) => setState(() => _fanLevel = value.round()),
          onFanChangeEnd: (_) => _persistControls(repo, device.deviceId),
          onMistChanged: (value) {
            setState(() => _mist = value);
            _persistControls(repo, device.deviceId);
          },
        ),
      ],
    );
  }

  Future<void> _persistControls(DeviceRepository repo, String deviceId) async {
    try {
      await repo.updateControls(
        deviceId: deviceId,
        manual: _manual,
        fanLevel: _fanLevel,
        mist: _mist,
      );
    } catch (_) {
      if (!mounted) return;
      setState(_syncFromDevice);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Control request was rejected or unavailable. Please refresh and try again.')),
      );
    }
  }

  void _syncFromDevice() {
    final device = ref.read(selectedDeviceProvider);
    if (device == null) return;
    _lastDeviceId = device.deviceId;
    _manual = device.snapshot.mode == 'MANUAL';
    _fanLevel = device.snapshot.fanLevel;
    _mist = device.snapshot.mist;
  }
}
