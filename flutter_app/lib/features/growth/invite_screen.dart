import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              InviteDashboard(),
              SizedBox(height: 12),
              GenerateInviteButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class GenerateInviteButton extends StatefulWidget {
  const GenerateInviteButton({super.key});

  @override
  State<GenerateInviteButton> createState() => _GenerateInviteButtonState();
}

class _GenerateInviteButtonState extends State<GenerateInviteButton> {
  final Dio _dio = Dio(BaseOptions(baseUrl: 'http://<backend-url>'));
  bool _loading = false;

  Future<void> _generateInvite() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/growth/create-link',
        options: Options(
          headers: const {'x-mock-domme-user-id': '00000000-0000-0000-0000-000000000001'},
        ),
      );
      final slug = response.data?['slug'] as String?;
      if (slug == null || !mounted) {
        return;
      }

      final fullLink = 'https://obeisance.app/invite/$slug';
      await Clipboard.setData(ClipboardData(text: fullLink));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite copied: $fullLink')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to generate invite link.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _loading ? null : _generateInvite,
        icon: const Icon(Icons.link),
        label: Text(_loading ? 'Generating...' : 'Generate Invite Link'),
      ),
    );
  }
}

class InviteDashboard extends StatefulWidget {
  const InviteDashboard({super.key});

  @override
  State<InviteDashboard> createState() => _InviteDashboardState();
}

class _InviteDashboardState extends State<InviteDashboard> {
  final Dio _dio = Dio(BaseOptions(baseUrl: 'http://<backend-url>'));
  bool _loading = true;
  int _activeSubs = 0;
  int _totalSlots = 0;
  int _remainingUses = 0;
  String? _inviteSlug;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/growth/stats',
        options: Options(
          headers: const {'x-mock-domme-user-id': '00000000-0000-0000-0000-000000000001'},
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeSubs = (response.data?['active_subs'] as int?) ?? 0;
        _totalSlots = (response.data?['total_slots'] as int?) ?? 0;
        _remainingUses = (response.data?['remaining_uses'] as int?) ?? 0;
        _inviteSlug = response.data?['invite_slug'] as String?;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activeSubs = 0;
        _totalSlots = 0;
        _remainingUses = 0;
        _inviteSlug = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Subs: $_activeSubs / $_totalSlots slots',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text('Remaining invite uses: $_remainingUses'),
                  const SizedBox(height: 6),
                  Text('Current link: ${_inviteSlug ?? 'No active invite'}'),
                ],
              ),
      ),
    );
  }
}
