import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

enum TempoCadence {
  daily,
  weekly,
  monthly;

  String get label => switch (this) {
        TempoCadence.daily => 'Daily',
        TempoCadence.weekly => 'Weekly',
        TempoCadence.monthly => 'Monthly',
      };

  static TempoCadence fromApi(String? value) {
    return TempoCadence.values.firstWhere(
      (entry) => entry.name == value,
      orElse: () => TempoCadence.weekly,
    );
  }
}

class TempoShareSettings {
  const TempoShareSettings({
    required this.sharingEnabled,
    required this.sharingPaused,
    required this.cadence,
  });

  final bool sharingEnabled;
  final bool sharingPaused;
  final TempoCadence cadence;

  factory TempoShareSettings.fromJson(Map<String, dynamic> json) {
    return TempoShareSettings(
      sharingEnabled: (json['sharing_enabled'] as bool?) ?? false,
      sharingPaused: (json['sharing_paused'] as bool?) ?? false,
      cadence: TempoCadence.fromApi(json['cadence'] as String?),
    );
  }
}

class TempoShareHistoryEntry {
  const TempoShareHistoryEntry({
    required this.id,
    required this.cadence,
    required this.averageVelocity,
    required this.sampleCount,
    required this.deliveryStatus,
    required this.deliveredAt,
  });

  final String id;
  final TempoCadence cadence;
  final double averageVelocity;
  final int sampleCount;
  final String deliveryStatus;
  final DateTime? deliveredAt;

  factory TempoShareHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TempoShareHistoryEntry(
      id: (json['id'] as String?) ?? '',
      cadence: TempoCadence.fromApi(json['cadence'] as String?),
      averageVelocity: (json['average_velocity'] as num?)?.toDouble() ?? 0,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      deliveryStatus: (json['delivery_status'] as String?) ?? 'unknown',
      deliveredAt: DateTime.tryParse((json['delivered_at'] as String?) ?? ''),
    );
  }
}

class TempoSharingService {
  TempoSharingService(this._dio);

  final Dio _dio;

  Future<TempoShareSettings> fetchSettings({required String hardwareUuid}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/metrics/tempo/settings',
      options: Options(headers: {'x-hardware-uuid': hardwareUuid}),
    );
    return TempoShareSettings.fromJson(response.data ?? const {});
  }

  Future<TempoShareSettings> updateSettings({
    required String hardwareUuid,
    required bool enabled,
    required bool paused,
    required TempoCadence cadence,
    required bool consentAcknowledged,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/metrics/tempo/settings',
      data: {
        'sharing_enabled': enabled,
        'sharing_paused': paused,
        'cadence': cadence.name,
        'consent_acknowledged': consentAcknowledged,
      },
      options: Options(headers: {'x-hardware-uuid': hardwareUuid}),
    );
    return TempoShareSettings.fromJson(response.data ?? const {});
  }

  Future<List<TempoShareHistoryEntry>> fetchHistory({required String hardwareUuid}) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/metrics/tempo/history',
      options: Options(headers: {'x-hardware-uuid': hardwareUuid}),
    );
    return (response.data ?? [])
        .whereType<Map>()
        .map((entry) => TempoShareHistoryEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  Future<List<TempoShareHistoryEntry>> fetchDomSummaries({
    required String dommeId,
    required TempoCadence cadence,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/metrics/tempo/domme/summaries',
      queryParameters: {'cadence': cadence.name},
      options: Options(headers: {'x-mock-domme-user-id': dommeId}),
    );
    return (response.data ?? [])
        .whereType<Map>()
        .map((entry) => TempoShareHistoryEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }
}

final tempoSharingServiceProvider = Provider<TempoSharingService>((ref) {
  return TempoSharingService(ref.read(apiClientProvider));
});
