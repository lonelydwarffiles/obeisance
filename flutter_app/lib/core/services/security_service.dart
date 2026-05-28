import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SecurityService centralises root detection, secure credential storage,
/// and SSL certificate pinning for the Obeisance MDM client.
class SecurityService {
  SecurityService({
    required this.baseUrl,
    required this.allowedSha256Pins,
    FlutterSecureStorage? secureStorage,
  }) : _storage = secureStorage ?? const FlutterSecureStorage();

  final String baseUrl;

  /// Base64-encoded SHA-256 digests of the DER-encoded server certificates
  /// or their public-key SPKIs that are trusted.
  final Set<String> allowedSha256Pins;

  final FlutterSecureStorage _storage;

  static const _kChannel = MethodChannel('app.obeisance/mdm');
  static const _kSecurityLockKey = 'security_lock';
  static const _kSessionTokenKey = 'session_token';
  static const _kPolicyCacheKey = 'cached_policy';

  /// Checks for root / jailbreak via the native MDM channel.
  /// If rooted: clears local secrets and throws [StateError].
  Future<void> enforceRootSecurityLock() async {
    final rooted = await _kChannel.invokeMethod<bool>('isRooted') ?? false;
    if (!rooted) return;

    await _storage.write(key: _kSecurityLockKey, value: 'true');
    await _storage.delete(key: _kSessionTokenKey);
    await _storage.delete(key: _kPolicyCacheKey);

    throw StateError('Security lock engaged: rooted device detected. Master unlock required.');
  }

  Future<bool> isSecurityLocked() async {
    final locked = await _storage.read(key: _kSecurityLockKey);
    return locked == 'true';
  }

  Future<void> storeSessionToken(String token) =>
      _storage.write(key: _kSessionTokenKey, value: token);

  Future<String?> readSessionToken() => _storage.read(key: _kSessionTokenKey);

  Future<void> storePolicyCache(String jsonPolicy) =>
      _storage.write(key: _kPolicyCacheKey, value: jsonPolicy);

  Future<String?> readPolicyCache() => _storage.read(key: _kPolicyCacheKey);

  /// Returns a [Dio] instance with SSL certificate pinning configured.
  /// Only certificates whose SHA-256 digest matches [allowedSha256Pins] are accepted.
  Dio buildPinnedDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient(context: SecurityContext(withTrustedRoots: true));
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        final sha = base64.encode(sha256.convert(cert.der).bytes);
        return allowedSha256Pins.contains(sha);
      };
      return client;
    };

    return dio;
  }
}
