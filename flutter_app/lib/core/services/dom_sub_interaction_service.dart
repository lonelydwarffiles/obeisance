import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class InteractionContractSummary {
  const InteractionContractSummary({
    required this.contractId,
    required this.domId,
    required this.subId,
    required this.status,
    required this.capabilities,
  });

  factory InteractionContractSummary.fromJson(Map<String, dynamic> json) {
    return InteractionContractSummary(
      contractId: (json['contract_id'] as String?) ?? '',
      domId: (json['dom_id'] as String?) ?? '',
      subId: (json['sub_id'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'unknown',
      capabilities: ((json['capabilities'] as List?) ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }

  final String contractId;
  final String domId;
  final String subId;
  final String status;
  final List<String> capabilities;
}

class InteractionCommandResult {
  const InteractionCommandResult({
    required this.commandId,
    required this.contractId,
    required this.commandType,
    required this.status,
  });

  factory InteractionCommandResult.fromJson(Map<String, dynamic> json) {
    return InteractionCommandResult(
      commandId: (json['command_id'] as String?) ?? '',
      contractId: (json['contract_id'] as String?) ?? '',
      commandType: (json['command_type'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'unknown',
    );
  }

  final String commandId;
  final String contractId;
  final String commandType;
  final String status;
}

class InteractionReceipt {
  const InteractionReceipt({
    required this.receiptId,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  factory InteractionReceipt.fromJson(Map<String, dynamic> json) {
    return InteractionReceipt(
      receiptId: (json['receipt_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      detail: (json['detail'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
    );
  }

  final String receiptId;
  final String title;
  final String detail;
  final DateTime? createdAt;
}

class ActiveConstraint {
  const ActiveConstraint({
    required this.key,
    required this.value,
    required this.reason,
    required this.expiresAt,
  });

  factory ActiveConstraint.fromJson(Map<String, dynamic> json) {
    return ActiveConstraint(
      key: (json['key'] as String?) ?? '',
      value: (json['value'] as String?) ?? '',
      reason: json['reason'] as String?,
      expiresAt: DateTime.tryParse((json['expires_at'] as String?) ?? ''),
    );
  }

  final String key;
  final String value;
  final String? reason;
  final DateTime? expiresAt;
}

class DomSubInteractionService {
  DomSubInteractionService(this._dio);

  final Dio _dio;

  Future<InteractionContractSummary> createContract({
    required String subId,
    String? deviceId,
    required List<String> capabilities,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/contracts',
      data: {
        'sub_id': subId,
        'device_id': deviceId,
        'capabilities': capabilities,
      },
    );
    return InteractionContractSummary.fromJson(response.data ?? const {});
  }

  Future<InteractionContractSummary> activateContract(String contractId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/activate',
    );
    return InteractionContractSummary.fromJson(response.data ?? const {});
  }

  Future<InteractionContractSummary> fetchContract(String contractId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId',
    );
    return InteractionContractSummary.fromJson(response.data ?? const {});
  }

  Future<InteractionContractSummary> pauseContract(
    String contractId, {
    String? reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/pause',
      data: {'reason': reason},
    );
    return InteractionContractSummary.fromJson(response.data ?? const {});
  }

  Future<InteractionContractSummary> revokeContract(
    String contractId, {
    String? reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/revoke',
      data: {'reason': reason},
    );
    return InteractionContractSummary.fromJson(response.data ?? const {});
  }

  Future<InteractionContractSummary> updateCapabilities(
    String contractId,
    List<String> capabilities,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/capabilities',
      data: {'capabilities': capabilities},
    );
    return InteractionContractSummary.fromJson(response.data ?? const {});
  }

  Future<InteractionCommandResult> issueCommand(
    String contractId, {
    required String commandType,
    Map<String, dynamic> payload = const {},
    bool requiresSubAck = false,
    int? executeAfterSeconds,
    int? expiresAfterSeconds,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/commands',
      data: {
        'command_type': commandType,
        'payload': payload,
        'requires_sub_ack': requiresSubAck,
        'execute_after_seconds': executeAfterSeconds,
        'expires_after_seconds': expiresAfterSeconds,
      },
    );
    return InteractionCommandResult.fromJson(response.data ?? const {});
  }

  Future<InteractionCommandResult> confirmCommand(String commandId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/commands/$commandId/confirm',
    );
    return InteractionCommandResult.fromJson(response.data ?? const {});
  }

  Future<InteractionCommandResult> acknowledgeCommand(
    String commandId, {
    required bool accepted,
    String? reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/commands/$commandId/ack',
      data: {'accepted': accepted, 'reason': reason},
    );
    return InteractionCommandResult.fromJson(response.data ?? const {});
  }

  Future<List<InteractionCommandResult>> fetchCommands(
    String contractId, {
    int limit = 30,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/commands',
      queryParameters: {'limit': limit},
    );
    return ((response.data?['commands'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) =>
            InteractionCommandResult.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<List<InteractionReceipt>> fetchReceipts(String contractId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/receipts',
    );
    return ((response.data?['receipts'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) =>
            InteractionReceipt.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<List<ActiveConstraint>> fetchActiveConstraints(
      String contractId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/active-constraints',
    );
    return ((response.data?['constraints'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) =>
            ActiveConstraint.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<List<ActiveConstraint>> triggerSafeMode(
    String contractId, {
    required String reason,
    int durationMinutes = 30,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/interactions/contracts/$contractId/safe-mode',
      data: {'reason': reason, 'duration_minutes': durationMinutes},
    );
    return ((response.data?['constraints'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) =>
            ActiveConstraint.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}

final domSubInteractionServiceProvider =
    Provider<DomSubInteractionService>((ref) {
  return DomSubInteractionService(ref.read(apiClientProvider));
});
