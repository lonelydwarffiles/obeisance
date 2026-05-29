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

final permissionChecklistProvider = StateNotifierProvider<
    PermissionChecklistController, Map<CompliancePermission, bool>>(
  (ref) => PermissionChecklistController(),
);

class PermissionChecklistController
    extends StateNotifier<Map<CompliancePermission, bool>> {
  PermissionChecklistController()
      : _mdmChannel = const MethodChannel('obeisance.mdm/compliance'),
        super({
          CompliancePermission.ignoreBatteryOptimizations: false,
          CompliancePermission.deviceAdmin: false,
          CompliancePermission.accessibilityService: false,
        });

  final MethodChannel _mdmChannel;

  bool get allGranted => state.values.every((value) => value);

  Future<void> openSettingsFor(CompliancePermission permission) async {
    switch (permission) {
      case CompliancePermission.ignoreBatteryOptimizations:
        await _invokeMdmPermission('openBatteryOptimizationSettings');
        return;
      case CompliancePermission.deviceAdmin:
        await _invokeMdmPermission('openDeviceAdminSettings');
        return;
      case CompliancePermission.accessibilityService:
        await _invokeMdmPermission('openAccessibilitySettings');
        return;
    }
  }

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
        state = {...state, permission: granted};
        await refresh();
        return;
      case CompliancePermission.accessibilityService:
        final granted =
            await _invokeMdmPermission('requestAccessibilityService');
        state = {...state, permission: granted};
        await refresh();
        return;
    }
  }

  Future<void> refresh() async {
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    final batteryNative =
        await _checkMdmPermission('checkIgnoreBatteryOptimizations');
    final deviceAdmin = await _checkMdmPermission('checkDeviceAdmin');
    final accessibility =
        await _checkMdmPermission('checkAccessibilityService');

    state = {
      CompliancePermission.ignoreBatteryOptimizations:
          batteryStatus.isGranted || batteryNative,
      CompliancePermission.deviceAdmin: deviceAdmin,
      CompliancePermission.accessibilityService: accessibility,
    };
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

  Future<bool> _checkMdmPermission(String method) async {
    try {
      final result = await _mdmChannel.invokeMethod<bool>(method);
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(
        () => ref.read(permissionChecklistProvider.notifier).refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(permissionChecklistProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    granted: permissionStates[
                            CompliancePermission.ignoreBatteryOptimizations] ??
                        false,
                    onGrant: () => controller
                        .grant(CompliancePermission.ignoreBatteryOptimizations),
                    onOpenSettings: () => controller.openSettingsFor(
                        CompliancePermission.ignoreBatteryOptimizations),
                  ),
                  _PermissionTile(
                    label: 'Device Admin',
                    granted:
                        permissionStates[CompliancePermission.deviceAdmin] ??
                            false,
                    onGrant: () =>
                        controller.grant(CompliancePermission.deviceAdmin),
                    onOpenSettings: () => controller
                        .openSettingsFor(CompliancePermission.deviceAdmin),
                  ),
                  _PermissionTile(
                    label: 'Accessibility Service',
                    granted: permissionStates[
                            CompliancePermission.accessibilityService] ??
                        false,
                    onGrant: () => controller
                        .grant(CompliancePermission.accessibilityService),
                    onOpenSettings: () => controller.openSettingsFor(
                        CompliancePermission.accessibilityService),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: controller.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Status'),
                    ),
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
                    backgroundColor: canProceed
                        ? const Color(0xFFE0B84C)
                        : Colors.grey.shade700,
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
    required this.onOpenSettings,
  });

  final String label;
  final bool granted;
  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF171717),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              granted ? 'Granted' : 'Required',
              style: TextStyle(
                color: granted ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: granted ? null : onGrant,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0B84C),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Grant'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onOpenSettings,
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
