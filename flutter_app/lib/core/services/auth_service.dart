import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'security_provider.dart';
import 'security_service.dart';

class AuthService {
  AuthService({
    required Dio dio,
    required SecurityService securityService,
  })  : _dio = dio,
        _securityService = securityService;

  final Dio _dio;
  final SecurityService _securityService;

  Future<bool> validateRegistrationToken(String inviteCode) async {
    if (inviteCode.trim().isEmpty) {
      return false;
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/growth/signup',
        data: {'invite_slug': inviteCode.trim()},
      );
      final isActive = response.data?['is_active'] as bool?;
      await _securityService.storeSessionToken(inviteCode.trim());
      return response.statusCode == 200 && (isActive ?? true);
    } on DioException {
      return false;
    }
  }
}

final authDioProvider = Provider<Dio>((ref) => ref.read(apiClientProvider));

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    dio: ref.read(authDioProvider),
    securityService: ref.read(securityServiceProvider),
  );
});
