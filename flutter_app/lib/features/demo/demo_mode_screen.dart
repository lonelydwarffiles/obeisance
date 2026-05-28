import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/demo_mode_provider.dart';

class DemoModeScreen extends ConsumerWidget {
  const DemoModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(demoPolicyProfileProvider);
    final demoModeEnabled = ref.watch(demoModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Mode'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        policy.policyName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(demoModeEnabled ? 'Read-only demo enabled' : 'Demo disabled'),
                      const SizedBox(height: 8),
                      for (final rule in policy.dailyRules) Text('• $rule'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () {
                    ref.read(demoModeProvider.notifier).disable();
                    context.go('/registration-gate');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0B84C),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text(
                    'Register',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
