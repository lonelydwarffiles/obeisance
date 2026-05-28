import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SystemTone { clinical, warm, authoritative }

class StyleProfile {
  const StyleProfile({
    required this.primaryColor,
    required this.backgroundImageUrl,
    required this.systemTone,
  });

  final Color primaryColor;
  final String? backgroundImageUrl;
  final SystemTone systemTone;

  factory StyleProfile.fromJson(Map<String, dynamic> json) {
    return StyleProfile(
      primaryColor: _parseColor(json['primaryColor'] as String?),
      backgroundImageUrl: json['backgroundImageUrl'] as String?,
      systemTone: _parseTone(json['systemTone'] as String?),
    );
  }

  static Color _parseColor(String? hex) {
    final raw = (hex ?? '#E0B84C').replaceAll('#', '');
    final normalized = raw.length == 6 ? 'FF$raw' : raw;
    return Color(int.parse(normalized, radix: 16));
  }

  static SystemTone _parseTone(String? tone) {
    switch ((tone ?? '').toLowerCase()) {
      case 'clinical':
        return SystemTone.clinical;
      case 'authoritative':
        return SystemTone.authoritative;
      default:
        return SystemTone.warm;
    }
  }
}

final _dioForThemeProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(baseUrl: 'http://<backend-url>'));
});

class StyleProfileNotifier extends AsyncNotifier<StyleProfile> {
  @override
  Future<StyleProfile> build() async {
    final dio = ref.read(_dioForThemeProvider);
    try {
      final res = await dio.get<Map<String, dynamic>>('/api/style-profile');
      return StyleProfile.fromJson(res.data ?? const {});
    } catch (_) {
      return const StyleProfile(
        primaryColor: Color(0xFFE0B84C),
        backgroundImageUrl: null,
        systemTone: SystemTone.warm,
      );
    }
  }
}

final styleProfileProvider =
    AsyncNotifierProvider<StyleProfileNotifier, StyleProfile>(StyleProfileNotifier.new);

final appThemeProvider = Provider<ThemeData>((ref) {
  final seed = ref.watch(styleProfileProvider).value?.primaryColor ?? const Color(0xFFE0B84C);
  return ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed));
});

String toneText(SystemTone tone, String neutralPrompt) {
  switch (tone) {
    case SystemTone.clinical:
      return neutralPrompt.replaceAll('dear', 'subject');
    case SystemTone.authoritative:
      return '$neutralPrompt, pet.';
    case SystemTone.warm:
      return '$neutralPrompt, dear.';
  }
}
