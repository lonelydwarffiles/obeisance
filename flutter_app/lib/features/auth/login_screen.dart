import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/demo_mode_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  static const _surface = Color(0xFF141024);
  static const _surfaceAlt = Color(0xFF1C1730);
  static const _royal = Color(0xFF7E57C2);
  static const _royalSoft = Color(0xFFB39DDB);
  static const _cta = Color(0xFFF6C453);

  Future<void> _copySubDownloadLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: 'https://obeisance.app/download'));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sub download link copied.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0A12),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF181325), Color(0xFF0E0C17)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: _royal.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Obeisance',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Direct structure. Clear consent. Designed for both sides of the dynamic.',
                          style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        _CtaBand(
                          onDomApply: () => context.go('/registration-gate'),
                          onSubDownload: () => _copySubDownloadLink(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flex(
                    direction: isWide ? Axis.horizontal : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _PathCard(
                          title: 'Dom Path',
                          subtitle: 'Lead with confidence, stay in control, grow your circle securely.',
                          actionLabel: 'Apply as Dom',
                          action: () => context.go('/registration-gate'),
                          background: _surfaceAlt,
                          accent: _royalSoft,
                        ),
                      ),
                      SizedBox(width: isWide ? 14 : 0, height: isWide ? 0 : 14),
                      Expanded(
                        child: _PathCard(
                          title: 'Sub Path',
                          subtitle: 'Download, onboard quickly, and step into guided structure at your pace.',
                          actionLabel: 'Download as Sub',
                          action: () => _copySubDownloadLink(context),
                          background: _surface,
                          accent: _cta,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _InfoCard(
                    title: 'What it can do',
                    items: [
                      'Coordinate communication and ritual touchpoints',
                      'Support invite-based connection and guided onboarding',
                      'Keep daily interactions structured across experience levels',
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _InfoCard(
                    title: 'Trust first',
                    items: [
                      'Security-first architecture',
                      'Privacy by default in account flow',
                      'Discreet experience and language choices',
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _royal.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'Built for every experience level — beginner to seasoned. '
                      'Welcoming in tone, direct in purpose.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CtaBand(
                    onDomApply: () => context.go('/registration-gate'),
                    onSubDownload: () => _copySubDownloadLink(context),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      ref.read(demoModeProvider.notifier).enable();
                      context.go('/demo');
                    },
                    child: const Text('Try Demo Mode'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.action,
    required this.background,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback action;
  final Color background;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: action,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF130F21),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF8F7AD6).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.circle, size: 8, color: Color(0xFFB39DDB)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaBand extends StatelessWidget {
  const _CtaBand({
    required this.onDomApply,
    required this.onSubDownload,
  });

  final VoidCallback onDomApply;
  final VoidCallback onSubDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onDomApply,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB39DDB),
              foregroundColor: Colors.black,
            ),
            child: const Text('Apply as Dom'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onSubDownload,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF6C453),
              foregroundColor: Colors.black,
            ),
            child: const Text('Download as Sub'),
          ),
        ),
      ],
    );
  }
}
