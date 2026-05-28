import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_service.dart';

class RegistrationGate extends ConsumerStatefulWidget {
  const RegistrationGate({super.key});

  @override
  ConsumerState<RegistrationGate> createState() => _RegistrationGateState();
}

class _RegistrationGateState extends ConsumerState<RegistrationGate> {
  final _inviteController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _validateInvite() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final isValid = await ref.read(authServiceProvider).validateRegistrationToken(_inviteController.text);
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _error = isValid ? null : 'Invite code is invalid or exhausted.';
    });

    if (isValid) {
      context.go('/permissions');
    }
  }

  Future<void> _requestAccess() async {
    try {
      final dio = ref.read(authDioProvider);
      await dio.post<Map<String, dynamic>>('/api/growth/request-access', data: {
        'note': 'Requested from app gatekeeper',
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Central has been notified.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to notify Central right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'Invitation Required',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _inviteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter invite code',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF171717),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _validateInvite,
                      child: _loading ? const CircularProgressIndicator() : const Text('Continue to Registration'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _requestAccess,
                    child: const Text('Request Access'),
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
