import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/demo_mode_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Obeisance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => context.go('/registration-gate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE0B84C),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Register'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => context.go('/dashboard'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Login as Controller'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      ref.read(demoModeProvider.notifier).enable();
                      context.go('/demo');
                    },
                    child: const Text('Try the Experience'),
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
