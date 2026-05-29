import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import 'central_dashboard_service.dart';

class CentralDashboardScreen extends ConsumerStatefulWidget {
  const CentralDashboardScreen({
    super.key,
    this.centralUserId = '',
  });

  final String centralUserId;

  @override
  ConsumerState<CentralDashboardScreen> createState() =>
      _CentralDashboardScreenState();
}

class _CentralDashboardScreenState
    extends ConsumerState<CentralDashboardScreen> {
  Timer? _refreshTimer;

  bool _loading = false;
  bool _refreshing = false;
  bool _bootstrapped = false;
  String? _error;
  CentralDashboardSummary? _summary;
  List<CentralTrendPoint> _trends = const [];

  @override
  void initState() {
    super.initState();
    _fetchDashboard(initialLoad: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: centralAutoRefreshSeconds),
      (_) => _fetchDashboard(),
    );
  }

  Future<void> _fetchDashboard({bool initialLoad = false}) async {
    final service = ref.read(centralDashboardServiceProvider);

    setState(() {
      _loading = initialLoad && !_bootstrapped;
      _refreshing = !initialLoad;
      _error = null;
    });

    try {
      final results = await Future.wait([
        service.fetchSummary(centralUserId: widget.centralUserId),
        service.fetchTrends(centralUserId: widget.centralUserId, days: 7),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _summary = results[0] as CentralDashboardSummary;
        _trends = results[1] as List<CentralTrendPoint>;
        _bootstrapped = true;
      });
    } on CentralDashboardException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.kind == CentralDashboardErrorKind.unauthorized ||
          error.kind == CentralDashboardErrorKind.forbidden) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go('/login');
          }
        });
      }
      setState(() {
        _error = error.message;
      });
    } on DioException {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load dashboard right now.';
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _openOverdueDomsDrilldown() async {
    final service = ref.read(centralDashboardServiceProvider);
    try {
      final entries = await service.fetchOverdueDoms(
        centralUserId: widget.centralUserId,
      );
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _DrilldownSheet(
          title: 'Overdue Dom Accounts',
          children: entries
              .map(
                (entry) => ListTile(
                  dense: true,
                  title: Text(
                      '${entry.username} • ${entry.overdueCycleCount} cycles'),
                  subtitle: Text(
                      'Latest overdue: ${_formatTimestamp(entry.latestOverdueAt)}'),
                ),
              )
              .toList(growable: false),
        ),
      );
    } on CentralDashboardException catch (error) {
      if (!mounted) {
        return;
      }
      _showInlineMessage(error.message);
    }
  }

  Future<void> _openInactiveDomsDrilldown() async {
    final service = ref.read(centralDashboardServiceProvider);
    try {
      final entries = await service.fetchInactiveDoms(
        centralUserId: widget.centralUserId,
      );
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _DrilldownSheet(
          title: 'Inactive Dom Accounts',
          children: entries
              .map(
                (entry) => ListTile(
                  dense: true,
                  title: Text(entry.username),
                  subtitle: Text(
                      'Renewal: ${_formatTimestamp(entry.billingRenewalDate)}'),
                ),
              )
              .toList(growable: false),
        ),
      );
    } on CentralDashboardException catch (error) {
      if (!mounted) {
        return;
      }
      _showInlineMessage(error.message);
    }
  }

  Future<void> _openPetitionsDrilldown() async {
    final service = ref.read(centralDashboardServiceProvider);
    try {
      final entries = await service.fetchOpenPetitions(
        centralUserId: widget.centralUserId,
      );
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _DrilldownSheet(
          title: 'Open Petitions',
          children: entries
              .map(
                (entry) => ListTile(
                  dense: true,
                  title: Text('${entry.domUsername} • ${entry.packageName}'),
                  subtitle: Text(entry.reason),
                  trailing: Text(
                    _formatTimestamp(entry.createdAt),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      );
    } on CentralDashboardException catch (error) {
      if (!mounted) {
        return;
      }
      _showInlineMessage(error.message);
    }
  }

  void _showInlineMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text('Central Dashboard'),
        backgroundColor: Colors.white,
      ),
      body: _loading && summary == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchDashboard(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_refreshing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  _KpiBanner(
                    title: 'Network Footprint',
                    subtitle: 'Current managed fleet and lease state',
                    metrics: [
                      _KpiMetric(
                        label: 'Total',
                        value: '${summary?.totalDevices ?? 0}',
                      ),
                      _KpiMetric(
                        label: 'Leased',
                        value: '${summary?.leasedDevices ?? 0}',
                      ),
                      _KpiMetric(
                        label: 'Pending',
                        value: '${summary?.leasePendingDevices ?? 0}',
                      ),
                      _KpiMetric(
                        label: 'Unclaimed',
                        value: '${summary?.unclaimedDevices ?? 0}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(points: _trends),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SimpleStatCard(
                          title: 'Dommes Active',
                          value: '${summary?.activeDommes ?? 0}',
                          icon: Icons.groups_2_outlined,
                          accent: const Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SimpleStatCard.button(
                          title: 'Dommes Inactive',
                          value: '${summary?.inactiveDommes ?? 0}',
                          icon: Icons.person_off_outlined,
                          accent: const Color(0xFFC62828),
                          onTap: _openInactiveDomsDrilldown,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SimpleStatCard(
                          title: 'Billing Pending',
                          value: '${summary?.pendingBillingCycles ?? 0}',
                          icon: Icons.schedule_outlined,
                          accent: const Color(0xFFEF6C00),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SimpleStatCard.button(
                          title: 'Billing Overdue',
                          value: '${summary?.overdueBillingCycles ?? 0}',
                          icon: Icons.warning_amber_outlined,
                          accent: const Color(0xFFD32F2F),
                          onTap: _openOverdueDomsDrilldown,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SimpleStatCard.button(
                    title: 'Open Petitions',
                    value: '${summary?.openPetitions ?? 0}',
                    icon: Icons.rule_folder_outlined,
                    accent: const Color(0xFF1565C0),
                    onTap: _openPetitionsDrilldown,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'At-Risk Doms (Overdue)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if ((summary?.overdueDoms ?? const <String>[])
                              .isEmpty)
                            const Text(
                              'No overdue Dom accounts right now.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          for (final username
                              in summary?.overdueDoms ?? const <String>[])
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.priority_high_rounded,
                                color: Color(0xFFD32F2F),
                              ),
                              title: Text(username),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recent Audit Activity',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if ((summary?.recentAuditEvents ??
                                  const <CentralRecentAuditEvent>[])
                              .isEmpty)
                            const Text(
                              'No recent audit events recorded yet.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          for (final event in summary?.recentAuditEvents ??
                              const <CentralRecentAuditEvent>[])
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title:
                                  Text('${event.action} • ${event.targetType}'),
                              subtitle: Text(_formatTimestamp(event.createdAt)),
                              leading: const Icon(Icons.feed_outlined),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _SimpleStatCard extends StatelessWidget {
  const _SimpleStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  }) : onTap = null;

  const _SimpleStatCard.button({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Card(child: content);
    }

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.points});

  final List<CentralTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final peak = points.fold<int>(0, (value, point) {
      final localMax = point.overdueBillingCycles > point.openPetitions
          ? point.overdueBillingCycles
          : point.openPetitions;
      return localMax > value ? localMax : value;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '7-Day Trend',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (points.isEmpty)
              const Text(
                'No trend data available.',
                style: TextStyle(color: Colors.black54),
              ),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${point.day.month.toString().padLeft(2, '0')}/${point.day.day.toString().padLeft(2, '0')}  '
                      'Overdue ${point.overdueBillingCycles}  Petition ${point.openPetitions}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: peak == 0
                                ? 0
                                : point.overdueBillingCycles / peak,
                            color: const Color(0xFFD32F2F),
                            backgroundColor: const Color(0xFFFFEBEE),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: peak == 0 ? 0 : point.openPetitions / peak,
                            color: const Color(0xFF1565C0),
                            backgroundColor: const Color(0xFFE3F2FD),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DrilldownSheet extends StatelessWidget {
  const _DrilldownSheet({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: children.isEmpty
                    ? const Center(
                        child: Text(
                          'No data available.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView(children: children),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiBanner extends StatelessWidget {
  const _KpiBanner({
    required this.title,
    required this.subtitle,
    required this.metrics,
  });

  final String title;
  final String subtitle;
  final List<_KpiMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFFB3E5FC)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: metrics
                .map(
                  (metric) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${metric.value} ',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          TextSpan(
                            text: metric.label,
                            style: const TextStyle(
                              color: Color(0xFFE1F5FE),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _KpiMetric {
  const _KpiMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}
