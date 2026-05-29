import 'package:dio/dio.dart';

import 'package:obeisance/core/models/geofence_rule.dart';
import 'package:obeisance/core/models/sleep_schedule.dart';
import 'package:obeisance/core/services/geofence_service.dart';
import 'package:obeisance/core/services/sleep_cycle_service.dart';

class PolicySyncService {
  PolicySyncService({
    required Dio dio,
    required GeofenceService geofenceService,
    required SleepCycleService sleepCycleService,
  })  : _dio = dio,
        _geofenceService = geofenceService,
        _sleepCycleService = sleepCycleService;

  final Dio _dio;
  final GeofenceService _geofenceService;
  final SleepCycleService _sleepCycleService;

  Future<void> syncAndApply(String deviceId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/policy/device/$deviceId');
    final data = response.data ?? const <String, dynamic>{};

    final geofence =
        Map<String, dynamic>.from((data['geofence'] as Map?) ?? const {});
    final latitude = (geofence['latitude'] as num?)?.toDouble();
    final longitude = (geofence['longitude'] as num?)?.toDouble();
    final radius = (geofence['radius_meters'] as num?)?.toDouble();
    final restricted =
        ((geofence['restricted_packages'] as List?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList(growable: false);

    if (latitude != null && longitude != null && radius != null) {
      await _geofenceService.start(
        rule: GeofenceRule(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radius,
          restrictedPackages: restricted,
        ),
      );
    } else {
      await _geofenceService.stop();
    }

    final sleep =
        Map<String, dynamic>.from((data['sleep'] as Map?) ?? const {});
    final start = sleep['start_time'] as String?;
    final end = sleep['end_time'] as String?;
    final nonEssential =
        ((sleep['non_essential_packages'] as List?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList(growable: false);

    if (start != null && end != null) {
      await _sleepCycleService.configureSchedule(
        schedule: SleepSchedule(startTime: start, endTime: end),
        nonEssentialPackages: nonEssential,
      );
    } else {
      await _sleepCycleService.disableSchedule();
    }
  }
}
