import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/demo_mode_provider.dart';
import '../dashboard/usage_screen.dart';
import '../growth/invite_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

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
          .map((entry) => LeaseSummary.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _leases = entries;
      });
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
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                title: const Text('Chat', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/chat?dommeId=${lease.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.assignment_turned_in_outlined, color: Colors.white),
                title: const Text('Assign Task', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Assign Task queued for ${lease.displayName}.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.redAccent),
                title: const Text('Lock Screen', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Lock command sent to ${lease.displayName}.')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
    return false;
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
                  const GenerateInviteButton(),
                  const SizedBox(height: 14),
                  for (final lease in _leases)
                    Dismissible(
                      key: ValueKey(lease.id),
                      direction: DismissDirection.horizontal,
                      confirmDismiss: (_) => _showQuickActions(lease),
                      background: _ActionHintBackground(alignment: Alignment.centerLeft),
                      secondaryBackground: _ActionHintBackground(alignment: Alignment.centerRight),
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
                                color: lease.online ? Colors.green : Colors.grey,
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
      displayName: (json['name'] as String?) ?? (json['id'] as String?) ?? 'Unknown Sub',
      batteryPercentage: (json['battery_percentage'] as int?) ?? 0,
      online: (json['online'] as bool?) ?? false,
    );
  }
}
