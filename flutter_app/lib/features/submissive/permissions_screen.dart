import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

enum CompliancePermission {
  ignoreBatteryOptimizations,
  deviceAdmin,
  accessibilityService,
}

final permissionChecklistProvider =
    StateNotifierProvider<PermissionChecklistController, Map<CompliancePermission, bool>>(
  (ref) => PermissionChecklistController(),
);

class PermissionChecklistController extends StateNotifier<Map<CompliancePermission, bool>> {
  PermissionChecklistController()
      : _mdmChannel = const MethodChannel('obeisance.mdm/compliance'),
        super({
          CompliancePermission.ignoreBatteryOptimizations: false,
          CompliancePermission.deviceAdmin: false,
          CompliancePermission.accessibilityService: false,
        });

  final MethodChannel _mdmChannel;

  bool get allGranted => state.values.every((value) => value);

  Future<void> grant(CompliancePermission permission) async {
    switch (permission) {
      case CompliancePermission.ignoreBatteryOptimizations:
        final status = await Permission.ignoreBatteryOptimizations.request();
        state = {
          ...state,
          permission: status.isGranted,
        };
        return;
      case CompliancePermission.deviceAdmin:
        final granted = await _invokeMdmPermission('requestDeviceAdmin');
        state = {
          ...state,
          permission: granted,
        };
        return;
      case CompliancePermission.accessibilityService:
        final granted = await _invokeMdmPermission('requestAccessibilityService');
        state = {
          ...state,
          permission: granted,
        };
        return;
    }
  }

  Future<bool> _invokeMdmPermission(String method) async {
    try {
      final result = await _mdmChannel.invokeMethod<bool>(method);
      return result ?? false;
    } on PlatformException {
      await openAppSettings();
      return false;
    } on MissingPluginException {
      await openAppSettings();
      return false;
    }
  }
}

class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionStates = ref.watch(permissionChecklistProvider);
    final controller = ref.read(permissionChecklistProvider.notifier);
    final canProceed = controller.allGranted;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('Compliance Checklist'),
        backgroundColor: const Color(0xFF111111),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _PermissionTile(
                    label: 'Ignore Battery Optimizations',
                    granted: permissionStates[CompliancePermission.ignoreBatteryOptimizations] ?? false,
                    onGrant: () => controller.grant(CompliancePermission.ignoreBatteryOptimizations),
                  ),
                  _PermissionTile(
                    label: 'Device Admin',
                    granted: permissionStates[CompliancePermission.deviceAdmin] ?? false,
                    onGrant: () => controller.grant(CompliancePermission.deviceAdmin),
                  ),
                  _PermissionTile(
                    label: 'Accessibility Service',
                    granted: permissionStates[CompliancePermission.accessibilityService] ?? false,
                    onGrant: () => controller.grant(CompliancePermission.accessibilityService),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: canProceed ? () => context.go('/apply') : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: canProceed ? const Color(0xFFE0B84C) : Colors.grey.shade700,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Proceed to Application'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.label,
    required this.granted,
    required this.onGrant,
  });

  final String label;
  final bool granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF171717),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          granted ? 'Granted' : 'Required',
          style: TextStyle(
            color: granted ? Colors.greenAccent : Colors.redAccent,
          ),
        ),
        trailing: FilledButton(
          onPressed: granted ? null : onGrant,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE0B84C),
            foregroundColor: Colors.black,
          ),
          child: const Text('Grant'),
        ),
      ),
    );
  }
}
