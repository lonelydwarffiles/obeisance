import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/chat/chat_screen.dart';
import '../features/domme/dashboard_screen.dart';
import '../features/submissive/apply_screen.dart';
import '../features/submissive/leashed_screen.dart';
import '../features/submissive/pending_screen.dart';
import '../features/submissive/permissions_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/permissions',
    routes: [
      GoRoute(
        path: '/login',
        redirect: (context, state) {
          final role = state.uri.queryParameters['role']?.toLowerCase();
          if (role == 'domme' || role == 'controller') {
            return '/dashboard';
          }
          return '/permissions';
        },
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
    ],
  );
});
