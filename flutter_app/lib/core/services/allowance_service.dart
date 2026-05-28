import 'dart:async';

import 'package:obeisance/core/services/mdm_bridge.dart';

typedef AllowanceRulesFetcher = Future<AllowanceRules> Function();

class AllowanceRules {
  const AllowanceRules({
    required this.dailyPackageAllowanceMs,
  });

  final Map<String, int> dailyPackageAllowanceMs;
}

class AllowanceService {
  AllowanceService({
    required MdmBridge mdmBridge,
    required AllowanceRulesFetcher fetchAllowanceRules,
    Duration pollInterval = const Duration(minutes: 5),
  })  : _mdmBridge = mdmBridge,
        _fetchAllowanceRules = fetchAllowanceRules,
        _pollInterval = pollInterval;

  final MdmBridge _mdmBridge;
  final AllowanceRulesFetcher _fetchAllowanceRules;
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

  Future<void> _runCycle() async {
    if (_runningCycle) {
      return;
    }
    _runningCycle = true;

    try {
      final screentimeByPackage = await _mdmBridge.getDailyScreentime();
      final allowanceRules = await _fetchAllowanceRules();

      final exceededPackages = <String>[];
      for (final rule in allowanceRules.dailyPackageAllowanceMs.entries) {
        final usedMs = screentimeByPackage[rule.key] ?? 0;
        if (usedMs > rule.value) {
          exceededPackages.add(rule.key);
        }
      }

      if (exceededPackages.isNotEmpty) {
        await _mdmBridge.setPackagesSuspended(exceededPackages, suspended: true);
      }
    } catch (_) {
      // Keep loop resilient to transient backend/platform errors.
    } finally {
      _runningCycle = false;
    }
  }
}
