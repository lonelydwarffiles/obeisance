import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/mqtt_service.dart';
import '../../core/services/telemetry_service.dart';

class LeashedScreen extends ConsumerStatefulWidget {
  const LeashedScreen({
    super.key,
    this.dommeName = 'Controller',
    this.dommeId = 'unknown',
  });

  final String dommeName;
  final String dommeId;

  @override
  ConsumerState<LeashedScreen> createState() => _LeashedScreenState();
}

class _LeashedScreenState extends ConsumerState<LeashedScreen> {
  static const _backendBaseUrl = 'http://<backend-url>';
  static const MethodChannel _taskChannel = MethodChannel('obeisance.mdm/tasks');

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  int _selectedIndex = 0;
  int _battery = 0;
  bool _connected = false;
  bool _loading = true;
  String? _error;
  List<HubTask> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final telemetry = await ref.read(telemetryServiceProvider).getDeviceStats();
      final response = await _dio.get<List<dynamic>>(
        '/api/tasks/daily',
        queryParameters: {'domme_id': widget.dommeId},
      );
      final parsedTasks = (response.data ?? [])
          .whereType<Map>()
          .map((entry) => HubTask.fromJson(Map<String, dynamic>.from(entry)))
          .toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _battery = (telemetry['battery_percentage'] as int?) ?? 0;
        _connected = ref.read(mqttServiceProvider).isConnected;
        _tasks = parsedTasks;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load monitored hub.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitTaskProof(HubTask task) async {
    try {
      await _taskChannel.invokeMethod('openCameraProof', {'task_id': task.id});
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = _tasks
            .map((entry) => entry.id == task.id ? entry.copyWith(completed: true) : entry)
            .toList();
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera proof flow unavailable on this build.')),
      );
    }
  }

  void _onBottomTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 1) {
      context.go('/chat?dommeId=${widget.dommeId}');
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Leashed Hub'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C1010),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE0B84C)),
                    ),
                    child: Text(
                      'Property of ${widget.dommeName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Card(
                    color: const Color(0xFF171717),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      title: const Text(
                        'Telemetry',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Battery: $_battery% • Connection: ${_connected ? 'Online' : 'Offline'}',
                        style: TextStyle(
                          color: _connected ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _tasks.length,
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return Card(
                          color: const Color(0xFF171717),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: CheckboxListTile(
                            value: task.completed,
                            onChanged: (_) => _submitTaskProof(task),
                            title: Text(
                              task.title,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: const Text(
                              'Tap checkbox to open camera and submit proof.',
                              style: TextStyle(color: Colors.white60),
                            ),
                            activeColor: const Color(0xFFE0B84C),
                            checkColor: Colors.black,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onBottomTap,
        backgroundColor: const Color(0xFF111111),
        selectedItemColor: const Color(0xFFE0B84C),
        unselectedItemColor: Colors.white70,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Hub',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}

class HubTask {
  const HubTask({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  factory HubTask.fromJson(Map<String, dynamic> json) {
    return HubTask(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Unnamed task',
      completed: (json['completed'] as bool?) ?? false,
    );
  }

  HubTask copyWith({bool? completed}) {
    return HubTask(
      id: id,
      title: title,
      completed: completed ?? this.completed,
    );
  }
}
