import 'dart:async';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:obeisance/core/models/geofence_rule.dart';
import 'package:obeisance/core/services/mdm_bridge.dart';

typedef FenceEventPublisher = Future<void> Function(
    Map<String, dynamic> payload);
typedef DeviceIdResolver = Future<String> Function();

class GeofenceService {
  GeofenceService({
    required MdmBridge mdmBridge,
    required FenceEventPublisher publishEvent,
    required DeviceIdResolver resolveDeviceId,
    required bool Function(DateTime now) isWorkingHours,
  })  : _mdmBridge = mdmBridge,
        _publishEvent = publishEvent,
        _resolveDeviceId = resolveDeviceId,
        _isWorkingHours = isWorkingHours;

  final MdmBridge _mdmBridge;
  final FenceEventPublisher _publishEvent;
  final DeviceIdResolver _resolveDeviceId;
  final bool Function(DateTime now) _isWorkingHours;
  GeofenceRule? _activeRule;

  StreamSubscription<bg.GeofenceEvent>? _geofenceSubscription;

  Future<void> start({
    required GeofenceRule rule,
  }) async {
    _activeRule = rule;

    await bg.BackgroundGeolocation.ready(
      bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 10,
        stopOnTerminate: false,
        startOnBoot: true,
        geofenceModeHighAccuracy: true,
      ),
    );

    _geofenceSubscription ??=
        bg.BackgroundGeolocation.onGeofence(_handleGeofenceEvent);

    await bg.BackgroundGeolocation.addGeofence(
      bg.Geofence(
        identifier: rule.identifier,
        latitude: rule.latitude,
        longitude: rule.longitude,
        radius: rule.radiusMeters,
        notifyOnEntry: true,
        notifyOnExit: true,
      ),
    );

    await bg.BackgroundGeolocation.startGeofences();
  }

  Future<void> stop() async {
    await _geofenceSubscription?.cancel();
    _geofenceSubscription = null;
    _activeRule = null;
    await bg.BackgroundGeolocation.stop();
  }

  Future<void> _handleGeofenceEvent(bg.GeofenceEvent event) async {
    final action = event.action.toUpperCase();
    if (action != 'ENTER' && action != 'EXIT') {
      return;
    }

    final now = DateTime.now();
    final deviceId = await _resolveDeviceId();
    final payload = <String, dynamic>{
      'event': action == 'ENTER' ? 'fence_enter' : 'fence_breach',
      'device_id': deviceId,
      'geofence_id': event.identifier,
      'transition': action,
      'timestamp': now.toUtc().toIso8601String(),
      'coords': event.location.coords.toMap(),
    };

    await _publishEvent(payload);

    if (action == 'ENTER') {
      final restricted = _activeRule?.restrictedPackages ?? const <String>[];
      if (restricted.isNotEmpty) {
        await _mdmBridge.setPackagesSuspended(restricted, suspended: true);
      }
      return;
    }

    if (_isWorkingHours(now)) {
      await _mdmBridge.triggerLock();
    }
  }
}

extension on bg.Coords {
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'heading': heading,
      'speed': speed,
    };
  }
}
