import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService(
    deviceInfoPlugin: DeviceInfoPlugin(),
    battery: Battery(),
    uuid: const Uuid(),
  );
});

class TelemetryService {
  TelemetryService({
    required DeviceInfoPlugin deviceInfoPlugin,
    required Battery battery,
    required Uuid uuid,
  })  : _deviceInfoPlugin = deviceInfoPlugin,
        _battery = battery,
        _uuid = uuid;

  static const _hardwareUuidKey = 'hardware_uuid';

  final DeviceInfoPlugin _deviceInfoPlugin;
  final Battery _battery;
  final Uuid _uuid;

  Future<Map<String, dynamic>> getDeviceStats() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final batteryPercentage = await _battery.batteryLevel;

    String? hardwareUuid;
    String deviceModel = 'Unknown device';
    String osVersion = Platform.operatingSystemVersion;

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      hardwareUuid = _sanitizeIdentifier(androidInfo.id);
      deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}'.trim();
      osVersion = 'Android ${androidInfo.version.release}';
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      hardwareUuid = _sanitizeIdentifier(iosInfo.identifierForVendor);
      deviceModel = iosInfo.utsname.machine;
      osVersion = '${iosInfo.systemName} ${iosInfo.systemVersion}';
    }

    hardwareUuid ??= sharedPreferences.getString(_hardwareUuidKey);
    hardwareUuid ??= _uuid.v4();

    await sharedPreferences.setString(_hardwareUuidKey, hardwareUuid);

    return {
      'hardware_uuid': hardwareUuid,
      'device_model': deviceModel,
      'os_version': osVersion,
      'battery_percentage': batteryPercentage,
    };
  }

  String? _sanitizeIdentifier(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
