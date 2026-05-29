import 'package:flutter/services.dart';

import 'package:obeisance/core/models/sleep_schedule.dart';

class MdmBridge {
  static const MethodChannel platform = MethodChannel('app.obeisance/mdm');

  Future<void> triggerLock() async {
    await platform.invokeMethod<void>('lockScreen');
  }

  Future<void> speakText(String message) async {
    await platform.invokeMethod<void>('speakText', {
      'message': message,
    });
  }

  Future<void> setWallpaper(String imageUrl) async {
    await platform.invokeMethod<void>('setWallpaper', {
      'imageUrl': imageUrl,
    });
  }

  Future<void> forceOpenUrl(String url) async {
    await platform.invokeMethod<void>('forceOpenUrl', {
      'url': url,
    });
  }

  Future<void> updateRedirectRules(Map<String, String> rules) async {
    await platform.invokeMethod<void>('updateRedirectRules', {
      'rules': rules,
    });
  }

  Future<List<String>> gatherAppInventory() async {
    final response =
        await platform.invokeMethod<List<dynamic>>('gatherAppInventory');
    if (response == null) {
      return const [];
    }
    return response.map((item) => item.toString()).toList(growable: false);
  }

  Future<Map<String, int>> gatherUsageStats() async {
    final response =
        await platform.invokeMapMethod<String, dynamic>('gatherUsageStats');
    if (response == null) {
      return const {};
    }
    return response
        .map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0));
  }

  Future<Map<String, int>> getDailyScreentime() async {
    final response =
        await platform.invokeMapMethod<String, dynamic>('getScreentimeStats');
    if (response == null) {
      return const {};
    }
    return response
        .map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0));
  }

  Future<void> startDnsFilter() async {
    await platform.invokeMethod<void>('startDnsFilter');
  }

  Future<void> stopDnsFilter() async {
    await platform.invokeMethod<void>('stopDnsFilter');
  }

  Future<void> startForegroundService() async {
    try {
      await platform.invokeMethod<void>('startForegroundService');
    } on MissingPluginException {
      // Native host channel is unavailable in some background isolates.
    }
  }

  Future<void> setPackagesSuspended(List<String> packageNames,
      {bool suspended = true}) async {
    await platform.invokeMethod<void>('setPackagesSuspended', {
      'packages': packageNames,
      'suspended': suspended,
    });
  }

  Future<void> scheduleSleepMode({
    required SleepSchedule schedule,
    required List<String> nonEssentialPackages,
  }) async {
    await platform.invokeMethod<void>('scheduleSleepMode', {
      ...schedule.toMap(),
      'non_essential_packages': nonEssentialPackages,
    });
  }

  Future<void> cancelSleepMode() async {
    await platform.invokeMethod<void>('cancelSleepMode');
  }

  Future<void> suspendPackage(String packageName) async {
    await setPackagesSuspended([packageName], suspended: true);
  }

  Future<void> updateTempoSettings({
    required String sensitivity,
    required List<String> restrictedPackages,
  }) async {
    await platform.invokeMethod<void>('updateTempoSettings', {
      'sensitivity': sensitivity,
      'restrictedPackages': restrictedPackages,
    });
  }

  Future<void> setKioskMode(bool enable) async {
    await platform.invokeMethod<void>('setKioskMode', {
      'enable': enable,
    });
  }

  Future<void> setNotificationFilter(bool deepFocus) async {
    await platform.invokeMethod<void>('setNotificationFilter', {
      'deepFocus': deepFocus,
    });
  }

  Future<void> forceNetworkTime() async {
    await platform.invokeMethod<void>('forceNetworkTime');
  }

  Future<void> executeNuclearWipe({required bool confirmed}) async {
    if (!confirmed) {
      throw ArgumentError.value(
          confirmed, 'confirmed', 'Wipe requires explicit confirmation');
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await platform.invokeMethod<void>('executeNuclearWipe', {
      'confirmed': true,
    });
  }

  Future<void> pauseMedia() async {
    await platform.invokeMethod<void>('pauseMedia');
  }

  Future<void> skipMedia() async {
    await platform.invokeMethod<void>('skipMedia');
  }

  Future<Map<String, String?>> getNowPlaying() async {
    final response =
        await platform.invokeMapMethod<String, dynamic>('getNowPlaying');
    if (response == null) {
      return const {
        'track': null,
        'artist': null,
      };
    }

    return {
      'track': response['track']?.toString(),
      'artist': response['artist']?.toString(),
    };
  }
}
