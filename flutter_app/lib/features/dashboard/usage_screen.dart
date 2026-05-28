import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/mdm_bridge.dart';
import '../../core/services/tempo_settings_service.dart';
import '../../core/services/usage_monitor.dart';

class UsageDashboardTile extends StatefulWidget {
  const UsageDashboardTile({super.key});

  @override
  State<UsageDashboardTile> createState() => _UsageDashboardTileState();
}

class _UsageDashboardTileState extends State<UsageDashboardTile> {
  final MdmBridge _mdmBridge = MdmBridge();
  final TempoSettingsService _tempoSettingsService = TempoSettingsService();
  late final UsageMonitor _usageMonitor = UsageMonitor(
    mdmBridge: _mdmBridge,
    fetchRules: _tempoSettingsService.loadUsageRules,
  );

  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;
  TempoSensitivity _sensitivity = TempoSensitivity.strict;
  UsageMonitorSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _loadSettings();
    await _usageMonitor.start();
    await _refreshUsage();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_refreshUsage());
    });
  }

  Future<void> _loadSettings() async {
    final sensitivity = await _tempoSettingsService.loadSensitivity();
    if (!mounted) {
      return;
    }
    setState(() {
      _sensitivity = sensitivity;
    });
    await _tempoSettingsService.saveSensitivity(sensitivity, mdmBridge: _mdmBridge);
  }

  Future<void> _refreshUsage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await _usageMonitor.getSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Usage data is unavailable.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _updateSensitivity(TempoSensitivity sensitivity) async {
    if (_sensitivity == sensitivity) {
      return;
    }
    setState(() {
      _sensitivity = sensitivity;
    });
    await _tempoSettingsService.saveSensitivity(sensitivity, mdmBridge: _mdmBridge);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _usageMonitor.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final usageLabel = snapshot == null ? '--' : _formatDuration(snapshot.totalUsageMs);
    final allowanceLabel =
        snapshot == null ? '--' : _formatDuration(snapshot.totalAllowanceMs);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.timelapse),
                SizedBox(width: 8),
                Text(
                  'Usage Tempo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading && snapshot == null)
              const LinearProgressIndicator(minHeight: 2)
            else
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'Usage Today',
                      value: usageLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricTile(
                      label: 'Allowance',
                      value: allowanceLabel,
                    ),
                  ),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 16),
            const Text(
              'Tempo',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TempoSensitivity.values.map((sensitivity) {
                return ChoiceChip(
                  label: Text(sensitivity.label),
                  selected: _sensitivity == sensitivity,
                  onSelected: (_) => unawaited(_updateSensitivity(sensitivity)),
                );
              }).toList(growable: false),
            ),
            if (snapshot != null && snapshot.exceededPackages.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Suspending ${snapshot.exceededPackages.length} high-tempo app(s).',
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '${duration.inHours}h ${minutes}m';
    }
    return '${duration.inMinutes}m';
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
