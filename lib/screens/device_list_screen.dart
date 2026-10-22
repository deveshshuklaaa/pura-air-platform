import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/device.dart';
import '../repositories/device_repository.dart';
import '../repositories/firestore_device_repository.dart';
import '../state/device_state.dart';
import '../widgets/device_card.dart';
import '../widgets/auth_required_view.dart';
import '../widgets/fade_slide.dart';
import '../widgets/section_header.dart';
import 'device_qr_screen.dart';
import 'qr_scan_screen.dart';

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesStreamProvider);
    final selectedId = ref.watch(selectedDeviceIdProvider);
    final repo = ref.watch(deviceRepositoryProvider);

    return devicesAsync.when(
      data: (devices) => Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionHeader(
                title: 'My Devices',
                subtitle: 'Monitor and control all units',
              ),
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('No devices yet.'),
                ),
              ...devices.asMap().entries.map((entry) {
                final index = entry.key;
                final device = entry.value;
                return FadeSlide(
                  delay: Duration(milliseconds: 60 * index),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DeviceCardWidget(
                      device: device,
                      selected: device.deviceId == selectedId,
                      onTap: () {
                        ref.read(selectedDeviceIdProvider.notifier).state =
                            device.deviceId;
                      },
                      onLongPress: () =>
                          _showDeviceActions(context, ref, repo, device),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 80),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton.extended(
              onPressed: () => _showAddDeviceSheet(context, ref, repo),
              icon: const Icon(Icons.add),
              label: const Text('Add Device'),
            ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) {
        if (err is FirebaseException && err.code == 'permission-denied') {
          return const AuthRequiredView(
            message:
                'Please sign in. Guest access may be disabled in Firebase.',
          );
        }
        return Center(child: Text('Error: $err'));
      },
    );
  }

  Future<void> _showAddDeviceSheet(
    BuildContext context,
    WidgetRef ref,
    DeviceRepository repo,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('Add Device', style: TextStyle(fontSize: 18)),
              ListTile(
                leading: const Icon(Icons.keyboard),
                title: const Text('Enter Device ID'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showManualAddDialog(context, repo);
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan QR Code'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final code = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const QrScanScreen()),
                  );
                  if (!context.mounted) return;
                  if (code == null || code.isEmpty) return;
                  final normalized = _normalizeDeviceId(code);
                  if (normalized == null) {
                    _showSnack(context, 'Invalid QR code');
                    return;
                  }
                  final isValid = await _validate(context, repo, normalized);
                  if (!context.mounted) return;
                  if (!isValid) {
                    _showSnack(context,
                        'Device not available (already claimed or not registered)');
                    return;
                  }
                  await _showNameDialog(context, repo, normalized);
                },
              ),
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Enter Pairing Code'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showPairingCodeDialog(context, repo);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showManualAddDialog(
    BuildContext context,
    DeviceRepository repo,
  ) async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    decoration: const InputDecoration(labelText: 'Device ID'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Device Name'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final id = idController.text.trim();
                    final name = nameController.text.trim();
                    if (id.isEmpty || name.isEmpty) {
                      setState(() => error = 'Both fields are required');
                      return;
                    }
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final isValid = await _validate(context, repo, id);
                    if (!context.mounted) return;
                    if (!isValid) {
                      setState(() => error =
                          'Device not available (already claimed or not registered)');
                      return;
                    }
                    if (!await _perform(context,
                        () => repo.addDevice(deviceId: id, name: name))) {
                      return;
                    }
                    if (!navigator.mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Device added')),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showNameDialog(
    BuildContext context,
    DeviceRepository repo,
    String deviceId,
  ) async {
    final nameController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Name this device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Device ID: $deviceId'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Device Name'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setState(() => error = 'Name is required');
                      return;
                    }
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    if (!await _perform(context,
                        () => repo.addDevice(deviceId: deviceId, name: name))) {
                      return;
                    }
                    if (!navigator.mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Device added')),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showPairingCodeDialog(
    BuildContext context,
    DeviceRepository repo,
  ) async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Pair Device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeController,
                    decoration:
                        const InputDecoration(labelText: 'Pairing Code'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Device Name'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final code = codeController.text.trim();
                    final name = nameController.text.trim();
                    if (code.isEmpty || name.isEmpty) {
                      setState(() => error = 'Both fields are required');
                      return;
                    }
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await repo.addDeviceWithPairingCode(
                        pairingCode: code,
                        name: name,
                      );
                    } on Exception catch (e) {
                      if (!navigator.mounted) return;
                      setState(() => error = e.toString());
                      return;
                    }
                    if (!navigator.mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Device paired')),
                    );
                  },
                  child: const Text('Pair'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDeviceActions(
    BuildContext context,
    WidgetRef ref,
    DeviceRepository repo,
    Device device,
  ) async {
    final rootContext = context;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(device.name, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 6),
              Text(
                'ID: ${device.deviceId}',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.qr_code),
                title: const Text('Show Device QR'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await Navigator.of(rootContext).push(
                    MaterialPageRoute(
                      builder: (_) => DeviceQrScreen(
                        deviceId: device.deviceId,
                        name: device.name,
                      ),
                    ),
                  );
                },
              ),
              if (device.canControl)
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Generate Pairing Code'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showPairingCodeGenerated(rootContext, repo, device);
                  },
                ),
              if (device.canControl)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Rename'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showRenameDialog(rootContext, repo, device);
                  },
                ),
              if (device.canControl && repo is FirestoreDeviceRepository)
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Manage sharing'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showSharing(rootContext, repo, device);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _confirmRemove(rootContext, ref, repo, device);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPairingCodeGenerated(
    BuildContext context,
    DeviceRepository repo,
    Device device,
  ) async {
    String? code;
    String? error;
    try {
      code = await repo.createPairingCode(deviceId: device.deviceId);
    } on Exception catch (e) {
      error = e.toString();
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pairing Code'),
          content: error != null
              ? Text(error, style: const TextStyle(color: Colors.redAccent))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Use this code to pair ${device.name}'),
                    const SizedBox(height: 12),
                    SelectableText(
                      code ?? '',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    DeviceRepository repo,
    Device device,
  ) async {
    final nameController = TextEditingController(text: device.name);
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Rename Device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Device Name'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setState(() => error = 'Name is required');
                      return;
                    }
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    if (!await _perform(
                        context,
                        () => repo.renameDevice(
                            deviceId: device.deviceId, name: name))) {
                      return;
                    }
                    if (!navigator.mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Device renamed')),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    DeviceRepository repo,
    Device device,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove device?'),
          content: Text('Remove ${device.name} from your account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;
    if (!await _perform(
        context, () => repo.removeDevice(deviceId: device.deviceId))) {
      return;
    }
    if (!navigator.mounted) return;
    ref.read(selectedDeviceIdProvider.notifier).state = null;
    messenger.showSnackBar(
      const SnackBar(content: Text('Device removed')),
    );
  }

  String? _normalizeDeviceId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final regex = RegExp(r'(PA-[A-Za-z0-9]+)');
    final match = regex.firstMatch(trimmed);
    if (match != null) return match.group(1);

    if (trimmed.contains('device_id')) {
      final jsonMatch =
          RegExp(r'"device_id"\s*:\s*"([^"]+)"').firstMatch(trimmed);
      if (jsonMatch != null) return jsonMatch.group(1);
    }

    return trimmed.length >= 4 ? trimmed : null;
  }

  Future<bool> _perform(
      BuildContext context, Future<void> Function() operation) async {
    try {
      await operation();
      return true;
    } on Exception catch (error) {
      if (context.mounted) _showSnack(context, error.toString());
      return false;
    }
  }

  Future<bool> _validate(
      BuildContext context, DeviceRepository repo, String id) async {
    try {
      return await repo.validateDeviceId(id);
    } on Exception catch (error) {
      if (context.mounted) _showSnack(context, error.toString());
      return false;
    }
  }

  Future<void> _showSharing(BuildContext context,
      FirestoreDeviceRepository repo, Device device) async {
    List<Map<String, dynamic>> members;
    try {
      members = await repo.listMembers(device.deviceId);
    } on Exception catch (error) {
      if (context.mounted) _showSnack(context, error.toString());
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Manage sharing'),
              content: SizedBox(
                  width: 320,
                  child: ListView(shrinkWrap: true, children: [
                    for (final member
                        in members.where((m) => m['role'] == 'shared'))
                      ListTile(
                        title: Text(member['uid'] as String),
                        trailing: TextButton(
                            child: const Text('Revoke'),
                            onPressed: () async {
                              final success = await _perform(
                                  dialogContext,
                                  () => repo.revokeMember(device.deviceId,
                                      member['uid'] as String));
                              if (success && dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                            }),
                      ),
                    if (!members.any((m) => m['role'] == 'shared'))
                      const Text('No shared members.'),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'))
              ],
            ));
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
