import 'dart:async';

import 'mdm_bridge.dart';

typedef UsageMonitorRulesFetcher = Future<UsageMonitorRules> Function();

class UsageMonitorRules {
  const UsageMonitorRules({
    required this.dailyPackageAllowanceMs,
  });

  final Map<String, int> dailyPackageAllowanceMs;
}

class UsageMonitorSnapshot {
  const UsageMonitorSnapshot({
    required this.usageByPackageMs,
    required this.allowanceByPackageMs,
    required this.exceededPackages,
  });

  final Map<String, int> usageByPackageMs;
  final Map<String, int> allowanceByPackageMs;
  final List<String> exceededPackages;

  int get totalUsageMs {
    return allowanceByPackageMs.keys.fold(0, (sum, packageName) {
      return sum + (usageByPackageMs[packageName] ?? 0);
    });
  }

  int get totalAllowanceMs => allowanceByPackageMs.values.fold(0, (sum, value) => sum + value);
}

class UsageMonitor {
  UsageMonitor({
    required MdmBridge mdmBridge,
    required UsageMonitorRulesFetcher fetchRules,
    Duration pollInterval = const Duration(seconds: 60),
  })  : _mdmBridge = mdmBridge,
        _fetchRules = fetchRules,
        _pollInterval = pollInterval;

  final MdmBridge _mdmBridge;
  final UsageMonitorRulesFetcher _fetchRules;
  final Duration _pollInterval;

  Timer? _timer;
  bool _runningCycle = false;

  Future<void> start() async {
    await _runCycle();
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) {
      unawaited(_runCycle());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<UsageMonitorSnapshot> getSnapshot() async {
    final usageByPackageMs = await _mdmBridge.getDailyScreentime();
    final rules = await _fetchRules();

    final exceededPackages = <String>[];
    for (final entry in rules.dailyPackageAllowanceMs.entries) {
      final currentUsage = usageByPackageMs[entry.key] ?? 0;
      if (currentUsage > entry.value) {
        exceededPackages.add(entry.key);
      }
    }

    return UsageMonitorSnapshot(
      usageByPackageMs: usageByPackageMs,
      allowanceByPackageMs: rules.dailyPackageAllowanceMs,
      exceededPackages: exceededPackages,
    );
  }

  Future<void> _runCycle() async {
    if (_runningCycle) {
      return;
    }
    _runningCycle = true;

    try {
      final snapshot = await getSnapshot();
      for (final packageName in snapshot.exceededPackages) {
        await _mdmBridge.suspendPackage(packageName);
      }
    } catch (_) {
      // Keep the worker resilient to transient platform failures.
    } finally {
      _runningCycle = false;
    }
  }
}
