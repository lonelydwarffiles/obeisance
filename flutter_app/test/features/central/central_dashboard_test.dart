import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obeisance/features/central/central_dashboard_screen.dart';
import 'package:obeisance/features/central/central_dashboard_service.dart';

class _FakeCentralDashboardService extends CentralDashboardService {
  _FakeCentralDashboardService() : super(Dio());

  @override
  Future<CentralDashboardSummary> fetchSummary(
      {String centralUserId = ''}) async {
    return CentralDashboardSummary(
      totalDevices: 10,
      leasedDevices: 5,
      leasePendingDevices: 2,
      unclaimedDevices: 3,
      activeDommes: 4,
      inactiveDommes: 1,
      pendingBillingCycles: 1,
      overdueBillingCycles: 2,
      openPetitions: 3,
      overdueDoms: <String>['dom_a'],
      recentAuditEvents: <CentralRecentAuditEvent>[
        CentralRecentAuditEvent(
          action: 'billing_cycle_paid',
          targetType: 'billing_cycle',
          createdAt: DateTime.utc(2026, 5, 28),
        ),
      ],
    );
  }

  @override
  Future<List<CentralTrendPoint>> fetchTrends({
    String centralUserId = '',
    int days = 7,
  }) async {
    return <CentralTrendPoint>[
      CentralTrendPoint(
        day: DateTime.utc(2026, 5, 27),
        overdueBillingCycles: 1,
        openPetitions: 1,
      ),
      CentralTrendPoint(
        day: DateTime.utc(2026, 5, 28),
        overdueBillingCycles: 2,
        openPetitions: 3,
      ),
    ];
  }

  @override
  Future<List<OverdueDomEntry>> fetchOverdueDoms(
      {String centralUserId = ''}) async {
    return const <OverdueDomEntry>[];
  }

  @override
  Future<List<InactiveDomEntry>> fetchInactiveDoms(
      {String centralUserId = ''}) async {
    return const <InactiveDomEntry>[];
  }

  @override
  Future<List<OpenPetitionEntry>> fetchOpenPetitions(
      {String centralUserId = ''}) async {
    return const <OpenPetitionEntry>[];
  }
}

void main() {
  test('central summary model parses expected fields', () {
    final summary = CentralDashboardSummary.fromJson(const {
      'total_devices': 9,
      'leased_devices': 3,
      'lease_pending_devices': 2,
      'unclaimed_devices': 4,
      'active_dommes': 2,
      'inactive_dommes': 1,
      'pending_billing_cycles': 3,
      'overdue_billing_cycles': 2,
      'open_petitions': 7,
      'overdue_doms': ['dom_a', 'dom_b'],
      'recent_audit_events': [
        {
          'action': 'policy_updated',
          'target_type': 'device_policy',
          'created_at': '2026-05-28T00:00:00Z',
        }
      ],
    });

    expect(summary.totalDevices, 9);
    expect(summary.openPetitions, 7);
    expect(summary.overdueDoms.length, 2);
    expect(summary.recentAuditEvents.first.targetType, 'device_policy');
  });

  testWidgets('central dashboard renders fetched values', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          centralDashboardServiceProvider.overrideWithValue(
            _FakeCentralDashboardService(),
          ),
        ],
        child: const MaterialApp(
          home: CentralDashboardScreen(centralUserId: 'superadmin-id'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Central Dashboard'), findsOneWidget);
    expect(find.text('Network Footprint'), findsOneWidget);
    expect(find.textContaining('Open Petitions'), findsWidgets);
  });
}
