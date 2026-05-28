import 'package:flutter_riverpod/flutter_riverpod.dart';

class DemoPolicyProfile {
  const DemoPolicyProfile({
    required this.policyName,
    required this.dailyRules,
    required this.readOnly,
  });

  final String policyName;
  final List<String> dailyRules;
  final bool readOnly;

  static const DemoPolicyProfile hardcoded = DemoPolicyProfile(
    policyName: 'Demo Obedience Protocol',
    dailyRules: [
      'Morning check-in at 08:00',
      'Hydration report every 3 hours',
      'Lights out by 22:00',
    ],
    readOnly: true,
  );
}

class DemoModeController extends StateNotifier<bool> {
  DemoModeController() : super(false);

  void enable() => state = true;
  void disable() => state = false;
}

final demoModeProvider = StateNotifierProvider<DemoModeController, bool>(
  (ref) => DemoModeController(),
);

final demoPolicyProfileProvider = Provider<DemoPolicyProfile>((ref) {
  return DemoPolicyProfile.hardcoded;
});
