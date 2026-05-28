import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/theme_provider.dart';

class VowScreen extends ConsumerStatefulWidget {
  const VowScreen({
    required this.deviceId,
    required this.controllerGreeting,
    super.key,
  });

  final String deviceId;
  final String controllerGreeting;

  @override
  ConsumerState<VowScreen> createState() => _VowScreenState();
}

class _VowScreenState extends ConsumerState<VowScreen> {
  static const _backendBaseUrl = 'http://<backend-url>';

  final TextEditingController _vowController = TextEditingController();
  late final Dio _dio;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(baseUrl: _backendBaseUrl));
  }

  Future<void> _sealVow() async {
    final text = _vowController.text.trim();
    if (text.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      await _dio.post(
        '/api/ritual/vow/${widget.deviceId}',
        data: {'content': text},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Vow sealed.')));
      _vowController.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Unable to seal vow right now.')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _vowController.dispose();
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = ref.watch(styleProfileProvider).value?.systemTone ?? SystemTone.warm;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Vow')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(widget.controllerGreeting,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                toneText(tone, "Write today's commitment"),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: _vowController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Your vow...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _sealVow,
                  child: Text(_submitting ? 'Sealing...' : 'Seal your Vow'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
