import 'package:shared_preferences/shared_preferences.dart';

import 'mdm_bridge.dart';
import 'usage_monitor.dart';

enum TempoSensitivity {
  strict,
  loose;

  String get label => switch (this) {
        TempoSensitivity.strict => 'Strict',
        TempoSensitivity.loose => 'Loose',
      };

  static TempoSensitivity fromStorage(String? value) {
    return TempoSensitivity.values.firstWhere(
      (candidate) => candidate.name == value,
      orElse: () => TempoSensitivity.strict,
    );
  }
}

class TempoSettingsService {
  static const sensitivityKey = 'tempo_sensitivity';
  static const restrictedPackages = <String>[
    'com.instagram.android',
    'com.google.android.youtube',
    'com.zhiliaoapp.musically',
    'com.twitter.android',
    'com.reddit.frontpage',
  ];

  static const _defaultAllowanceByPackageMs = <String, int>{
    'com.instagram.android': 30 * 60 * 1000,
    'com.google.android.youtube': 45 * 60 * 1000,
    'com.zhiliaoapp.musically': 20 * 60 * 1000,
    'com.twitter.android': 20 * 60 * 1000,
    'com.reddit.frontpage': 20 * 60 * 1000,
  };

  Future<TempoSensitivity> loadSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    return TempoSensitivity.fromStorage(prefs.getString(sensitivityKey));
  }

  Future<void> saveSensitivity(
    TempoSensitivity sensitivity, {
    required MdmBridge mdmBridge,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sensitivityKey, sensitivity.name);
    await mdmBridge.updateTempoSettings(
      sensitivity: sensitivity.name,
      restrictedPackages: restrictedPackages,
    );
  }

  Future<UsageMonitorRules> loadUsageRules() async {
    return const UsageMonitorRules(
      dailyPackageAllowanceMs: _defaultAllowanceByPackageMs,
    );
  }
}
