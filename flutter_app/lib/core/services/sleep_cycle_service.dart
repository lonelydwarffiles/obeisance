import 'package:obeisance/core/models/sleep_schedule.dart';
import 'package:obeisance/core/services/mdm_bridge.dart';

class SleepCycleService {
  SleepCycleService({required MdmBridge mdmBridge}) : _mdmBridge = mdmBridge;

  final MdmBridge _mdmBridge;

  Future<void> configureSchedule({
    required SleepSchedule schedule,
    required List<String> nonEssentialPackages,
  }) async {
    await _mdmBridge.scheduleSleepMode(
      schedule: schedule,
      nonEssentialPackages: nonEssentialPackages,
    );
  }

  Future<void> disableSchedule() async {
    await _mdmBridge.cancelSleepMode();
  }
}
