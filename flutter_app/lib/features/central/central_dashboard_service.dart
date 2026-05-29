import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api_client.dart';

enum CentralDashboardErrorKind {
  unauthorized,
  forbidden,
  timeout,
  offline,
  server,
  unknown,
}

class CentralDashboardException implements Exception {
  const CentralDashboardException(this.kind);

  final CentralDashboardErrorKind kind;

  String get message {
    switch (kind) {
      case CentralDashboardErrorKind.unauthorized:
        return 'Session expired. Please sign in again.';
      case CentralDashboardErrorKind.forbidden:
        return 'This account does not have Central dashboard access.';
      case CentralDashboardErrorKind.timeout:
        return 'Request timed out. Pull to refresh.';
      case CentralDashboardErrorKind.offline:
        return 'Network unavailable. Check your connection.';
      case CentralDashboardErrorKind.server:
        return 'Central service is unavailable. Try again shortly.';
      case CentralDashboardErrorKind.unknown:
        return 'Unable to load dashboard right now.';
    }
  }
}

class CentralDashboardService {
  CentralDashboardService(this._dio);

  final Dio _dio;

  Future<CentralDashboardSummary> fetchSummary({
    String centralUserId = '',
  }) async {
    final data = await _getJson(
      '/api/central/dashboard-summary',
      centralUserId: centralUserId,
    );
    return CentralDashboardSummary.fromJson(data);
  }

  Future<List<CentralTrendPoint>> fetchTrends({
    String centralUserId = '',
    int days = 7,
  }) async {
    final data = await _getJson(
      '/api/central/trends',
      centralUserId: centralUserId,
      queryParameters: {'days': days},
    );
    return ((data['points'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => CentralTrendPoint.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
  }

  Future<List<OverdueDomEntry>> fetchOverdueDoms({
    String centralUserId = '',
  }) async {
    final data = await _getJson(
      '/api/central/drilldown/overdue-doms',
      centralUserId: centralUserId,
    );
    return ((data['doms'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => OverdueDomEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
  }

  Future<List<InactiveDomEntry>> fetchInactiveDoms({
    String centralUserId = '',
  }) async {
    final data = await _getJson(
      '/api/central/drilldown/inactive-doms',
      centralUserId: centralUserId,
    );
    return ((data['doms'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => InactiveDomEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
  }

  Future<List<OpenPetitionEntry>> fetchOpenPetitions({
    String centralUserId = '',
  }) async {
    final data = await _getJson(
      '/api/central/drilldown/open-petitions',
      centralUserId: centralUserId,
    );
    return ((data['petitions'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => OpenPetitionEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    String centralUserId = '',
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final headers = <String, dynamic>{};
      if (centralUserId.isNotEmpty) {
        headers['X-Mock-User-Id'] = centralUserId;
      }
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return response.data ?? const <String, dynamic>{};
    } on DioException catch (error) {
      throw CentralDashboardException(_mapError(error));
    }
  }

  CentralDashboardErrorKind _mapError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 401) {
      return CentralDashboardErrorKind.unauthorized;
    }
    if (statusCode == 403) {
      return CentralDashboardErrorKind.forbidden;
    }
    if (statusCode != null && statusCode >= 500) {
      return CentralDashboardErrorKind.server;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return CentralDashboardErrorKind.timeout;
    }
    if (error.type == DioExceptionType.connectionError) {
      return CentralDashboardErrorKind.offline;
    }
    return CentralDashboardErrorKind.unknown;
  }
}

class CentralDashboardSummary {
  const CentralDashboardSummary({
    required this.totalDevices,
    required this.leasedDevices,
    required this.leasePendingDevices,
    required this.unclaimedDevices,
    required this.activeDommes,
    required this.inactiveDommes,
    required this.pendingBillingCycles,
    required this.overdueBillingCycles,
    required this.openPetitions,
    required this.overdueDoms,
    required this.recentAuditEvents,
  });

  factory CentralDashboardSummary.fromJson(Map<String, dynamic> json) {
    return CentralDashboardSummary(
      totalDevices: (json['total_devices'] as num?)?.toInt() ?? 0,
      leasedDevices: (json['leased_devices'] as num?)?.toInt() ?? 0,
      leasePendingDevices: (json['lease_pending_devices'] as num?)?.toInt() ?? 0,
      unclaimedDevices: (json['unclaimed_devices'] as num?)?.toInt() ?? 0,
      activeDommes: (json['active_dommes'] as num?)?.toInt() ?? 0,
      inactiveDommes: (json['inactive_dommes'] as num?)?.toInt() ?? 0,
      pendingBillingCycles: (json['pending_billing_cycles'] as num?)?.toInt() ?? 0,
      overdueBillingCycles: (json['overdue_billing_cycles'] as num?)?.toInt() ?? 0,
      openPetitions: (json['open_petitions'] as num?)?.toInt() ?? 0,
      overdueDoms: ((json['overdue_doms'] as List?) ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(growable: false),
      recentAuditEvents: ((json['recent_audit_events'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((entry) => CentralRecentAuditEvent.fromJson(Map<String, dynamic>.from(entry)))
          .toList(growable: false),
    );
  }

  final int totalDevices;
  final int leasedDevices;
  final int leasePendingDevices;
  final int unclaimedDevices;
  final int activeDommes;
  final int inactiveDommes;
  final int pendingBillingCycles;
  final int overdueBillingCycles;
  final int openPetitions;
  final List<String> overdueDoms;
  final List<CentralRecentAuditEvent> recentAuditEvents;
}

class CentralRecentAuditEvent {
  const CentralRecentAuditEvent({
    required this.action,
    required this.targetType,
    required this.createdAt,
  });

  factory CentralRecentAuditEvent.fromJson(Map<String, dynamic> json) {
    return CentralRecentAuditEvent(
      action: (json['action'] as String?) ?? 'unknown_action',
      targetType: (json['target_type'] as String?) ?? 'unknown_target',
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String action;
  final String targetType;
  final DateTime createdAt;
}

class CentralTrendPoint {
  const CentralTrendPoint({
    required this.day,
    required this.overdueBillingCycles,
    required this.openPetitions,
  });

  factory CentralTrendPoint.fromJson(Map<String, dynamic> json) {
    return CentralTrendPoint(
      day: DateTime.tryParse((json['day'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      overdueBillingCycles: (json['overdue_billing_cycles'] as num?)?.toInt() ?? 0,
      openPetitions: (json['open_petitions'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime day;
  final int overdueBillingCycles;
  final int openPetitions;
}

class OverdueDomEntry {
  const OverdueDomEntry({
    required this.domId,
    required this.username,
    required this.overdueCycleCount,
    required this.latestOverdueAt,
  });

  factory OverdueDomEntry.fromJson(Map<String, dynamic> json) {
    return OverdueDomEntry(
      domId: (json['dom_id'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      overdueCycleCount: (json['overdue_cycle_count'] as num?)?.toInt() ?? 0,
      latestOverdueAt: DateTime.tryParse((json['latest_overdue_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String domId;
  final String username;
  final int overdueCycleCount;
  final DateTime latestOverdueAt;
}

class InactiveDomEntry {
  const InactiveDomEntry({
    required this.domId,
    required this.username,
    required this.billingRenewalDate,
  });

  factory InactiveDomEntry.fromJson(Map<String, dynamic> json) {
    return InactiveDomEntry(
      domId: (json['dom_id'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      billingRenewalDate: DateTime.tryParse((json['billing_renewal_date'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String domId;
  final String username;
  final DateTime billingRenewalDate;
}

class OpenPetitionEntry {
  const OpenPetitionEntry({
    required this.petitionId,
    required this.domId,
    required this.domUsername,
    required this.packageName,
    required this.reason,
    required this.createdAt,
  });

  factory OpenPetitionEntry.fromJson(Map<String, dynamic> json) {
    return OpenPetitionEntry(
      petitionId: (json['petition_id'] as String?) ?? '',
      domId: (json['dom_id'] as String?) ?? '',
      domUsername: (json['dom_username'] as String?) ?? '',
      packageName: (json['package_name'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String petitionId;
  final String domId;
  final String domUsername;
  final String packageName;
  final String reason;
  final DateTime createdAt;
}

final centralDashboardServiceProvider = Provider<CentralDashboardService>((ref) {
  return CentralDashboardService(ref.read(apiClientProvider));
});
