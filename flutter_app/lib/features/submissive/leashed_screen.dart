import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/dom_sub_interaction_service.dart';
import '../../core/services/mqtt_service.dart';
import '../../core/services/telemetry_service.dart';
import '../../core/services/tempo_sharing_service.dart';

class LeashedScreen extends ConsumerStatefulWidget {
  const LeashedScreen({
    super.key,
    this.dommeName = 'Controller',
    this.dommeId = 'unknown',
    this.contractId = '',
  });

  final String dommeName;
  final String dommeId;
  final String contractId;

  @override
  ConsumerState<LeashedScreen> createState() => _LeashedScreenState();
}

class _LeashedScreenState extends ConsumerState<LeashedScreen> {
  static const _backendBaseUrl = 'http://<backend-url>';
  static const MethodChannel _taskChannel =
      MethodChannel('obeisance.mdm/tasks');

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  int _selectedIndex = 0;
  int _battery = 0;
  bool _connected = false;
  bool _loading = true;
  String? _error;
  String? _hardwareUuid;
  List<HubTask> _tasks = const [];
  TempoShareSettings? _tempoSettings;
  List<TempoShareHistoryEntry> _tempoHistory = const [];
  bool _tempoBusy = false;
  String? _tempoError;
  bool _interactionBusy = false;
  String? _interactionError;
  List<ActiveConstraint> _activeConstraints = const [];
  List<InteractionReceipt> _interactionReceipts = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final telemetry =
          await ref.read(telemetryServiceProvider).getDeviceStats();
      final hardwareUuid = telemetry['hardware_uuid'] as String?;
      final response = await _dio.get<List<dynamic>>(
        '/api/tasks/daily',
        queryParameters: {'domme_id': widget.dommeId},
      );
      final parsedTasks = (response.data ?? [])
          .whereType<Map>()
          .map((entry) => HubTask.fromJson(Map<String, dynamic>.from(entry)))
          .toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _battery = (telemetry['battery_percentage'] as int?) ?? 0;
        _hardwareUuid = hardwareUuid;
        _connected = ref.read(mqttServiceProvider).isConnected;
        _tasks = parsedTasks;
      });
      if (hardwareUuid != null && hardwareUuid.isNotEmpty) {
        await _refreshTempoSharing(hardwareUuid);
      }
      await _refreshInteractions();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load monitored hub.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshInteractions() async {
    if (widget.contractId.isEmpty) {
      return;
    }
    try {
      final service = ref.read(domSubInteractionServiceProvider);
      final constraints =
          await service.fetchActiveConstraints(widget.contractId);
      final receipts = await service.fetchReceipts(widget.contractId);
      if (!mounted) {
        return;
      }
      setState(() {
        _activeConstraints = constraints;
        _interactionReceipts = receipts;
        _interactionError = null;
      });
    } on DioException {
      if (!mounted) {
        return;
      }
      setState(() {
        _interactionError = 'Interaction data unavailable right now.';
      });
    }
  }

  Future<void> _triggerSafeMode() async {
    if (widget.contractId.isEmpty) {
      return;
    }
    setState(() {
      _interactionBusy = true;
    });

    try {
      final service = ref.read(domSubInteractionServiceProvider);
      await service.triggerSafeMode(
        widget.contractId,
        reason: 'Sub requested emergency decompression window',
        durationMinutes: 30,
      );
      await _refreshInteractions();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency safe mode activated for 30m.')),
      );
    } on DioException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to trigger safe mode.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _interactionBusy = false;
        });
      }
    }
  }

  Future<void> _refreshTempoSharing(String hardwareUuid) async {
    try {
      final service = ref.read(tempoSharingServiceProvider);
      final settings = await service.fetchSettings(hardwareUuid: hardwareUuid);
      final history = await service.fetchHistory(hardwareUuid: hardwareUuid);
      if (!mounted) {
        return;
      }
      setState(() {
        _tempoSettings = settings;
        _tempoHistory = history;
        _tempoError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tempoError = 'Tempo sharing unavailable right now.';
      });
    }
  }

  Future<void> _saveTempoSettings({
    required bool enabled,
    required bool paused,
    required TempoCadence cadence,
    required bool consentAcknowledged,
  }) async {
    final hardwareUuid = _hardwareUuid;
    if (hardwareUuid == null || hardwareUuid.isEmpty) {
      return;
    }
    setState(() {
      _tempoBusy = true;
    });
    try {
      final service = ref.read(tempoSharingServiceProvider);
      final settings = await service.updateSettings(
        hardwareUuid: hardwareUuid,
        enabled: enabled,
        paused: paused,
        cadence: cadence,
        consentAcknowledged: consentAcknowledged,
      );
      final history = await service.fetchHistory(hardwareUuid: hardwareUuid);
      if (!mounted) {
        return;
      }
      setState(() {
        _tempoSettings = settings;
        _tempoHistory = history;
        _tempoError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tempoError = 'Could not update tempo sharing.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _tempoBusy = false;
        });
      }
    }
  }

  Future<void> _submitTaskProof(HubTask task) async {
    try {
      await _taskChannel.invokeMethod('openCameraProof', {'task_id': task.id});
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = _tasks
            .map((entry) =>
                entry.id == task.id ? entry.copyWith(completed: true) : entry)
            .toList();
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Camera proof flow unavailable on this build.')),
      );
    }
  }

  void _onBottomTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 1) {
      context.go('/chat?dommeId=${widget.dommeId}');
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Leashed Hub'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C1010),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE0B84C)),
                    ),
                    child: Text(
                      'Property of ${widget.dommeName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Card(
                    color: const Color(0xFF171717),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      title: const Text(
                        'Telemetry',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Battery: $_battery% • Connection: ${_connected ? 'Online' : 'Offline'}',
                        style: TextStyle(
                          color: _connected
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (widget.contractId.isNotEmpty)
                    Card(
                      color: const Color(0xFF171717),
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Interaction Status',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _interactionBusy
                                      ? null
                                      : _triggerSafeMode,
                                  child: const Text('Emergency Safe Mode'),
                                ),
                              ],
                            ),
                            if (_interactionError != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  _interactionError!,
                                  style:
                                      const TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            if (_activeConstraints.isEmpty)
                              const Text(
                                'No active interaction constraints.',
                                style: TextStyle(color: Colors.white60),
                              ),
                            for (final item in _activeConstraints.take(4))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${item.key}: ${item.value}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  item.reason ?? 'No reason provided',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                                trailing: Text(
                                  _formatTimestamp(item.expiresAt),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12),
                                ),
                              ),
                            const SizedBox(height: 4),
                            const Text(
                              'Recent Receipts',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600),
                            ),
                            if (_interactionReceipts.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'No interaction receipts yet.',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              ),
                            for (final receipt in _interactionReceipts.take(3))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  receipt.title,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  receipt.detail,
                                  style: const TextStyle(color: Colors.white60),
                                ),
                                trailing: Text(
                                  _formatTimestamp(receipt.createdAt),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _tasks.length + 1,
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          final settings = _tempoSettings;
                          return Card(
                            color: const Color(0xFF171717),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tempo Sharing',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Optional. When enabled, only your linked Controller receives period summaries.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  SwitchListTile(
                                    value: settings?.sharingEnabled ?? false,
                                    onChanged: (_tempoBusy || settings == null)
                                        ? null
                                        : (value) => _saveTempoSettings(
                                              enabled: value,
                                              paused: false,
                                              cadence: settings.cadence,
                                              consentAcknowledged: value,
                                            ),
                                    title: const Text(
                                      'Enable consent-based sharing',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    subtitle: const Text(
                                      'You can revoke this at any time.',
                                      style: TextStyle(color: Colors.white60),
                                    ),
                                    activeColor: const Color(0xFFE0B84C),
                                  ),
                                  Row(
                                    children: [
                                      const Text(
                                        'Cadence:',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                      const SizedBox(width: 12),
                                      DropdownButton<TempoCadence>(
                                        dropdownColor: const Color(0xFF222222),
                                        value: settings?.cadence ??
                                            TempoCadence.weekly,
                                        items: TempoCadence.values
                                            .map(
                                              (cadence) => DropdownMenuItem(
                                                value: cadence,
                                                child: Text(
                                                  cadence.label,
                                                  style: const TextStyle(
                                                      color: Colors.white),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (_tempoBusy ||
                                                settings == null ||
                                                !settings.sharingEnabled)
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                _saveTempoSettings(
                                                  enabled:
                                                      settings.sharingEnabled,
                                                  paused:
                                                      settings.sharingPaused,
                                                  cadence: value,
                                                  consentAcknowledged: true,
                                                );
                                              },
                                      ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: (_tempoBusy ||
                                                settings == null ||
                                                !settings.sharingEnabled)
                                            ? null
                                            : () => _saveTempoSettings(
                                                  enabled:
                                                      settings.sharingEnabled,
                                                  paused:
                                                      !settings.sharingPaused,
                                                  cadence: settings.cadence,
                                                  consentAcknowledged: true,
                                                ),
                                        child: Text(
                                          settings?.sharingPaused == true
                                              ? 'Resume'
                                              : 'Pause',
                                          style: const TextStyle(
                                              color: Color(0xFFE0B84C)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_tempoError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        _tempoError!,
                                        style: const TextStyle(
                                            color: Colors.redAccent),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Sharing History',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (_tempoHistory.isEmpty)
                                    const Text(
                                      'No summaries sent yet.',
                                      style: TextStyle(color: Colors.white60),
                                    ),
                                  for (final entry in _tempoHistory.take(4))
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        '${entry.cadence.label} • ${entry.deliveryStatus}',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                      subtitle: Text(
                                        'Avg ${entry.averageVelocity.toStringAsFixed(1)} px/s • Samples ${entry.sampleCount}',
                                        style: const TextStyle(
                                            color: Colors.white60),
                                      ),
                                      trailing: Text(
                                        _formatTimestamp(entry.deliveredAt),
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }
                        final task = _tasks[index - 1];
                        return Card(
                          color: const Color(0xFF171717),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: CheckboxListTile(
                            value: task.completed,
                            onChanged: (_) => _submitTaskProof(task),
                            title: Text(
                              task.title,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: const Text(
                              'Tap checkbox to open camera and submit proof.',
                              style: TextStyle(color: Colors.white60),
                            ),
                            activeColor: const Color(0xFFE0B84C),
                            checkColor: Colors.black,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onBottomTap,
        backgroundColor: const Color(0xFF111111),
        selectedItemColor: const Color(0xFFE0B84C),
        unselectedItemColor: Colors.white70,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Hub',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return '--';
    }
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class HubTask {
  const HubTask({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  factory HubTask.fromJson(Map<String, dynamic> json) {
    return HubTask(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Unnamed task',
      completed: (json['completed'] as bool?) ?? false,
    );
  }

  HubTask copyWith({bool? completed}) {
    return HubTask(
      id: id,
      title: title,
      completed: completed ?? this.completed,
    );
  }
}
