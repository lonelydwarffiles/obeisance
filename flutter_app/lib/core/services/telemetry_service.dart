import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService(
    deviceInfoPlugin: DeviceInfoPlugin(),
    battery: Battery(),
    uuid: const Uuid(),
    networkInfo: NetworkInfo(),
  );
});

class TelemetryService {
  TelemetryService({
    required DeviceInfoPlugin deviceInfoPlugin,
    required Battery battery,
    required Uuid uuid,
    required NetworkInfo networkInfo,
  })  : _deviceInfoPlugin = deviceInfoPlugin,
        _battery = battery,
        _uuid = uuid,
        _networkInfo = networkInfo;

  static const _hardwareUuidKey = 'hardware_uuid';

  final DeviceInfoPlugin _deviceInfoPlugin;
  final Battery _battery;
  final Uuid _uuid;
  final NetworkInfo _networkInfo;

  Future<Map<String, dynamic>> getDeviceStats() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final batteryPercentage = await _battery.batteryLevel;
    final currentLocation = await _getCurrentLocation();
    final wifiSsid = await _networkInfo.getWifiName();

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
      'current_location': currentLocation,
      'wifi_ssid': _normalizeSsid(wifiSsid),
    };
  }

  Future<Map<String, double>?> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition();
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
    } catch (_) {
      return null;
    }
  }

  String? _sanitizeIdentifier(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeSsid(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.replaceAll('"', '');
  }
}
