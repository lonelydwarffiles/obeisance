import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/telemetry_service.dart';

class ApplyScreen extends ConsumerStatefulWidget {
  const ApplyScreen({super.key});

  @override
  ConsumerState<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends ConsumerState<ApplyScreen> {
  static const _backendBaseUrl = 'http://<backend-url>';

  final _formKey = GlobalKey<FormState>();
  final _mistressIdController = TextEditingController();
  final _dio = Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _mistressIdController.dispose();
    _dio.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final telemetry = await ref.read(telemetryServiceProvider).getDeviceStats();
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/apply',
        data: {
          ...telemetry,
          'static_link_id': _mistressIdController.text.trim(),
        },
      );

      if (!mounted) {
        return;
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        context.go('/leashed-pending');
        return;
      }

      setState(() {
        _errorMessage = 'Submission denied. Try again.';
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            error.response?.data is Map<String, dynamic> && error.response?.data['detail'] is String
                ? error.response?.data['detail'] as String
                : 'Unable to submit to the leash right now.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Unable to submit to the leash right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Beg for the Collar',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Present yourself and wait for your keeper to decide.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _mistressIdController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Mistress ID / Static Link ID',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: const Color(0xFF171717),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a Mistress ID / Static Link ID.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE0B84C),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : const Text(
                                'Submit to the Leash',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
