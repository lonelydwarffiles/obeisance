import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/registration_gate.dart';
import '../features/billing/payment_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/demo/demo_mode_screen.dart';
import '../features/domme/dashboard_screen.dart';
import '../features/economy/store_screen.dart';
import '../features/growth/invite_screen.dart';
import '../features/notes/knot_screen.dart';
import '../features/praise/praise_gallery.dart';
import '../features/ritual/vow_screen.dart';
import '../features/submissive/apply_screen.dart';
import '../features/submissive/leashed_screen.dart';
import '../features/submissive/pending_screen.dart';
import '../features/submissive/permissions_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/registration-gate',
        builder: (context, state) => const RegistrationGate(),
      ),
      GoRoute(
        path: '/demo',
        builder: (context, state) => const DemoModeScreen(),
      ),
      GoRoute(
        path: '/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/apply',
        builder: (context, state) => const ApplyScreen(),
      ),
      GoRoute(
        path: '/leashed-pending',
        builder: (context, state) => const PendingScreen(),
      ),
      GoRoute(
        path: '/leashed',
        builder: (context, state) => LeashedScreen(
          dommeName: state.uri.queryParameters['dommeName'] ?? 'Controller',
          dommeId: state.uri.queryParameters['dommeId'] ?? 'unknown',
        ),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => ChatScreen(
          dommeId: state.uri.queryParameters['dommeId'] ?? 'unknown',
        ),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/growth',
        builder: (context, state) => const InviteScreen(),
      ),
      GoRoute(
        path: '/store',
        builder: (context, state) => StoreScreen(
          deviceId: state.uri.queryParameters['deviceId'] ?? '',
          currencyName: state.uri.queryParameters['currencyName'] ?? 'Compliance Credits',
        ),
      ),
      GoRoute(
        path: '/knot',
        builder: (context, state) => KnotScreen(
          deviceId: state.uri.queryParameters['deviceId'] ?? '',
          isDomme: state.uri.queryParameters['role'] == 'domme',
          dommeUserId: state.uri.queryParameters['dommeUserId'],
        ),
      ),
      GoRoute(
        path: '/vow',
        builder: (context, state) => VowScreen(
          deviceId: state.uri.queryParameters['deviceId'] ?? '',
          controllerGreeting:
              state.uri.queryParameters['greeting'] ?? 'Good day.',
        ),
      ),
      GoRoute(
        path: '/praise',
        builder: (context, state) => PraiseGallery(
          deviceId: state.uri.queryParameters['deviceId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/billing',
        builder: (context, state) => PaymentDashboard(
          dommeId: state.uri.queryParameters['dommeId'] ?? '',
          deviceId: state.uri.queryParameters['deviceId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/billing-settings',
        builder: (context, state) => DommeBillingSettings(
          dommeId: state.uri.queryParameters['dommeId'] ?? '',
        ),
      ),
    ],
  );
});
