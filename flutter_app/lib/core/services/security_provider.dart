import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'security_service.dart';

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService(
    baseUrl: backendBaseUrl,
    allowedSha256Pins: const {},
  );
});
