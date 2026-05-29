import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/demo_mode_provider.dart';
import '../../core/services/dom_sub_interaction_service.dart';
import '../../core/services/tempo_sharing_service.dart';
import '../dashboard/usage_screen.dart';
import '../growth/invite_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    this.dommeId = 'unknown',
  });

  final String dommeId;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const _backendBaseUrl = 'http://<backend-url>';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  bool _loading = true;
  String? _error;
  List<LeaseSummary> _leases = const [];
  List<TempoShareHistoryEntry> _tempoSummaries = const [];
  TempoCadence _selectedCadence = TempoCadence.daily;
  final Map<String, String> _contractIdsBySubId = {};

  @override
  void initState() {
    super.initState();
    _fetchLeases();
  }

  Future<void> _fetchLeases() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.get<List<dynamic>>('/api/manage/leases');
      final entries = (response.data ?? [])
          .whereType<Map>()
          .map((entry) =>
              LeaseSummary.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _leases = entries;
      });
      await _fetchTempoSummaries();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load leases.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchTempoSummaries() async {
    if (widget.dommeId == 'unknown') {
      return;
    }
    try {
      final entries =
          await ref.read(tempoSharingServiceProvider).fetchDomSummaries(
                dommeId: widget.dommeId,
                cadence: _selectedCadence,
              );
      if (!mounted) {
        return;
      }
      setState(() {
        _tempoSummaries = entries;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tempoSummaries = const [];
      });
    }
  }

  Future<bool> _showQuickActions(LeaseSummary lease) async {
    if (!mounted) {
      return false;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.chat_bubble_outline, color: Colors.white),
                title:
                    const Text('Chat', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/chat?dommeId=${lease.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.assignment_turned_in_outlined,
                    color: Colors.white),
                title: const Text('Assign Task',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Assign Task queued for ${lease.displayName}.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune_outlined, color: Colors.white),
                title: const Text('Open Interaction Console',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  final contractId = await _resolveContractId(lease);
                  if (!mounted) {
                    return;
                  }
                  Navigator.pop(context);
                  context.go(
                    '/interaction-console?subId=${lease.id}&subName=${Uri.encodeQueryComponent(lease.displayName)}&contractId=${contractId ?? ''}',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.phonelink_setup_outlined,
                    color: Colors.white),
                title: const Text('Open Leashed With Contract',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  final contractId = await _resolveContractId(lease);
                  if (!mounted) {
                    return;
                  }
                  Navigator.pop(context);
                  context.go(
                    '/leashed?dommeId=${widget.dommeId}&dommeName=${Uri.encodeQueryComponent('Controller')}&contractId=${contractId ?? ''}',
                  );
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.handshake_outlined, color: Colors.white),
                title: const Text('Create/Refresh Contract',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _createOrRefreshContract(lease);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.play_circle_outline, color: Colors.white),
                title: const Text('Activate Contract',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _activateContract(lease);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.lock_outline, color: Colors.redAccent),
                title: const Text('Lock Screen',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _sendLockCommand(lease);
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined,
                    color: Colors.white),
                title: const Text('View Receipts',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _showInteractionReceipts(lease);
                },
              ),
            ],
          ),
        );
      },
    );
    return false;
  }

  Future<void> _createOrRefreshContract(LeaseSummary lease) async {
    try {
      final service = ref.read(domSubInteractionServiceProvider);
      final created = await service.createContract(
        subId: lease.id,
        capabilities: const [
          'lock_device',
          'message_sub',
          'restrict_packages',
        ],
      );
      if (!mounted) {
        return;
      }
      _contractIdsBySubId[lease.id] = created.contractId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contract ready for ${lease.displayName}.')),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final contractId = _extractContractIdFromError(error);
      if (contractId != null) {
        _contractIdsBySubId[lease.id] = contractId;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Using existing contract for ${lease.displayName}.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create contract.')),
      );
    }
  }

  Future<void> _activateContract(LeaseSummary lease) async {
    final contractId = await _resolveContractId(lease);
    if (contractId == null) {
      return;
    }
    try {
      final service = ref.read(domSubInteractionServiceProvider);
      await service.activateContract(contractId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contract activated for ${lease.displayName}.')),
      );
    } on DioException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not activate contract.')),
      );
    }
  }

  Future<void> _sendLockCommand(LeaseSummary lease) async {
    final contractId = await _resolveContractId(lease);
    if (contractId == null) {
      return;
    }

    try {
      final service = ref.read(domSubInteractionServiceProvider);
      final command = await service.issueCommand(
        contractId,
        commandType: 'lock_device',
        requiresSubAck: true,
        payload: {'source': 'domme_dashboard'},
        expiresAfterSeconds: 1200,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            command.status == 'pending_confirmation'
                ? 'Lock command awaiting dom confirmation.'
                : 'Lock command queued for ${lease.displayName}.',
          ),
        ),
      );

      if (command.status == 'pending_confirmation') {
        await service.confirmCommand(command.commandId);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lock command confirmed and queued.')),
        );
      }
    } on DioException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not issue lock command.')),
      );
    }
  }

  Future<void> _showInteractionReceipts(LeaseSummary lease) async {
    final contractId = await _resolveContractId(lease);
    if (contractId == null) {
      return;
    }

    try {
      final service = ref.read(domSubInteractionServiceProvider);
      final receipts = await service.fetchReceipts(contractId);
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        builder: (context) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Interaction Receipts • ${lease.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (receipts.isEmpty)
                  const ListTile(
                    title: Text('No receipts yet.'),
                  ),
                for (final item in receipts)
                  ListTile(
                    dense: true,
                    title: Text(item.title),
                    subtitle: Text(item.detail),
                    trailing: Text(
                      _formatTimestamp(item.createdAt),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    } on DioException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load receipts.')),
      );
    }
  }

  Future<String?> _resolveContractId(LeaseSummary lease) async {
    var contractId = _contractIdsBySubId[lease.id];
    if (contractId != null && contractId.isNotEmpty) {
      return contractId;
    }
    await _createOrRefreshContract(lease);
    contractId = _contractIdsBySubId[lease.id];
    return contractId;
  }

  String? _extractContractIdFromError(DioException error) {
    final responseData = error.response?.data;
    if (responseData is! Map) {
      return null;
    }
    final detail = responseData['detail'];
    if (detail is Map) {
      final contractId = detail['contract_id'];
      if (contractId is String && contractId.isNotEmpty) {
        return contractId;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demoMode = ref.watch(demoModeProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Controller Dashboard'),
        backgroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchLeases,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (demoMode)
                    const Card(
                      margin: EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(Icons.visibility),
                        title: Text('DemoMode'),
                        subtitle: Text('Read-only sample data is active'),
                      ),
                    ),
                  const UsageDashboardTile(),
                  const InviteDashboard(),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tempo Summaries',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Period:'),
                              const SizedBox(width: 10),
                              DropdownButton<TempoCadence>(
                                value: _selectedCadence,
                                items: TempoCadence.values
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry,
                                        child: Text(entry.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _selectedCadence = value;
                                  });
                                  _fetchTempoSummaries();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_tempoSummaries.isEmpty)
                            const Text(
                              'No summaries available.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          for (final summary in _tempoSummaries.take(6))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${summary.cadence.label} • ${summary.deliveryStatus}',
                              ),
                              subtitle: Text(
                                'Avg ${summary.averageVelocity.toStringAsFixed(1)} px/s • Samples ${summary.sampleCount}',
                              ),
                              trailing: Text(
                                _formatTimestamp(summary.deliveredAt),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const GenerateInviteButton(),
                  const SizedBox(height: 14),
                  for (final lease in _leases)
                    Dismissible(
                      key: ValueKey(lease.id),
                      direction: DismissDirection.horizontal,
                      confirmDismiss: (_) => _showQuickActions(lease),
                      background: _ActionHintBackground(
                          alignment: Alignment.centerLeft),
                      secondaryBackground: _ActionHintBackground(
                          alignment: Alignment.centerRight),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(lease.displayName),
                          subtitle: Text('Battery ${lease.batteryPercentage}%'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 12,
                                color:
                                    lease.online ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(lease.online ? 'Online' : 'Offline'),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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

class _ActionHintBackground extends StatelessWidget {
  const _ActionHintBackground({
    required this.alignment,
  });

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFE6ECF5),
      child: const Text(
        'Swipe for actions',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class LeaseSummary {
  const LeaseSummary({
    required this.id,
    required this.displayName,
    required this.batteryPercentage,
    required this.online,
  });

  final String id;
  final String displayName;
  final int batteryPercentage;
  final bool online;

  factory LeaseSummary.fromJson(Map<String, dynamic> json) {
    return LeaseSummary(
      id: (json['id'] as String?) ?? '',
      displayName:
          (json['name'] as String?) ?? (json['id'] as String?) ?? 'Unknown Sub',
      batteryPercentage: (json['battery_percentage'] as int?) ?? 0,
      online: (json['online'] as bool?) ?? false,
    );
  }
}
