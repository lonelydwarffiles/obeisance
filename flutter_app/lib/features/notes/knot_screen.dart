import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class KnotScreen extends StatefulWidget {
  const KnotScreen({
    required this.deviceId,
    required this.isDomme,
    this.dommeUserId,
    super.key,
  });

  final String deviceId;
  final bool isDomme;
  final String? dommeUserId;

  @override
  State<KnotScreen> createState() => _KnotScreenState();
}

class _KnotScreenState extends State<KnotScreen> {
  static const _backendBaseUrl = 'http://<backend-url>';

  late final Dio _dio;
  final TextEditingController _sharedController = TextEditingController();
  final TextEditingController _dossierController = TextEditingController();

  bool _loading = true;
  bool _syncing = false;
  String? _error;
  Timer? _debounce;
  int _activeTab = 0;

  Map<String, dynamic> get _headers {
    final headers = <String, dynamic>{};
    if (widget.dommeUserId != null && widget.dommeUserId!.isNotEmpty) {
      headers['x-mock-domme-user-id'] = widget.dommeUserId;
    }
    return headers;
  }

  @override
  void initState() {
    super.initState();
    _dio = Dio(
      BaseOptions(
        baseUrl: _backendBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shared = await _dio.get<Map<String, dynamic>>(
        '/api/notes/shared/${widget.deviceId}',
        options: Options(headers: _headers),
      );
      _sharedController.text = (shared.data?['content'] as String?) ?? '';

      if (widget.isDomme) {
        final dossier = await _dio.get<Map<String, dynamic>>(
          '/api/notes/dossier/${widget.deviceId}',
          options: Options(headers: _headers),
        );
        _dossierController.text = (dossier.data?['private_notes'] as String?) ?? '';
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load notes.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleAutoSave({required bool dossier}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (dossier) {
        _syncDossier(silent: true);
      } else {
        _syncShared(silent: true);
      }
    });
  }

  Future<void> _syncShared({bool silent = false}) => _sync(
        endpoint: '/api/notes/shared/${widget.deviceId}',
        payload: {'content': _sharedController.text},
        successMessage: 'Knot synced.',
        silent: silent,
      );

  Future<void> _syncDossier({bool silent = false}) {
    if (!widget.isDomme) return Future.value();
    return _sync(
      endpoint: '/api/notes/dossier/${widget.deviceId}',
      payload: {'private_notes': _dossierController.text},
      successMessage: 'Dossier synced.',
      silent: silent,
    );
  }

  Future<void> _sync({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String successMessage,
    required bool silent,
  }) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await _dio.put(endpoint, data: payload, options: Options(headers: _headers));
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Sync failed.')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncCurrentTab() {
    if (_activeTab == 0) return _syncShared();
    return _syncDossier();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sharedController.dispose();
    _dossierController.dispose();
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabCount = widget.isDomme ? 2 : 1;
    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('The Knot'),
          bottom: TabBar(
            onTap: (index) => setState(() => _activeTab = index),
            tabs: [
              const Tab(text: 'Knot'),
              if (widget.isDomme) const Tab(text: 'Dossier'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _EditorPane(
                          controller: _sharedController,
                          hint: 'Shared space for both parties...',
                          onChanged: (_) => _scheduleAutoSave(dossier: false),
                        ),
                        if (widget.isDomme)
                          _EditorPane(
                            controller: _dossierController,
                            hint: 'Private dossier notes (Domme only)...',
                            onChanged: (_) => _scheduleAutoSave(dossier: true),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _syncing ? null : _syncCurrentTab,
          label: Text(_syncing ? 'Syncing...' : 'Sync'),
          icon: const Icon(Icons.sync),
        ),
      ),
    );
  }
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}
