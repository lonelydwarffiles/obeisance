import 'package:flutter/services.dart';

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
    final response = await platform.invokeMethod<List<dynamic>>('gatherAppInventory');
    if (response == null) {
      return const [];
    }
    return response.map((item) => item.toString()).toList(growable: false);
  }

  Future<Map<String, int>> gatherUsageStats() async {
    final response = await platform.invokeMapMethod<String, dynamic>('gatherUsageStats');
    if (response == null) {
      return const {};
    }
    return response.map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0));
  }

  Future<void> pauseMedia() async {
    await platform.invokeMethod<void>('pauseMedia');
  }

  Future<void> skipMedia() async {
    await platform.invokeMethod<void>('skipMedia');
  }

  Future<Map<String, String?>> getNowPlaying() async {
    final response = await platform.invokeMapMethod<String, dynamic>('getNowPlaying');
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
