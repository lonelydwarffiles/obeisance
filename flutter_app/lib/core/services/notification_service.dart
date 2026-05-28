import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHandler {
  NotificationHandler();

  static const String _anchorChannelId = 'ANCHOR';
  static const String _directiveChannelId = 'DIRECTIVE';
  static const String _systemAlertChannelId = 'SYSTEM_ALERT';
  static const Duration _taskDebounceWindow = Duration(seconds: 10);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _taskDebounceActive = false;
  Timer? _taskDebounceTimer;
  int _currentTaskAlertId = 4100;
  int _taskAlertSequence = 4100;

  static const int _anchorNotificationId = 4001;
  static const int _systemAlertNotificationId = 4002;

  Future<void> showTaskAlert(String title, String body) async {
    await _ensureInitialized();
    if (!_taskDebounceActive) {
      _taskAlertSequence += 1;
      _currentTaskAlertId = _taskAlertSequence;
      _taskDebounceActive = true;
    }
    _restartTaskDebounceWindow();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _directiveChannelId,
        'Directive',
        channelDescription: 'Task and chat directives.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notifications.show(
      _currentTaskAlertId,
      title,
      body,
      details,
    );
  }

  Future<void> showEmergencyPage(String message) async {
    await _ensureInitialized();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _systemAlertChannelId,
        'System Alert',
        channelDescription: 'Emergency page commands.',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
      ),
    );

    await _notifications.show(
      _systemAlertNotificationId,
      'Emergency Page',
      message,
      details,
    );
  }

  Future<void> updateAnchor(String status) async {
    await _ensureInitialized();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _anchorChannelId,
        'Anchor',
        channelDescription: 'Persistent service anchor notifications.',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        ongoing: true,
        onlyAlertOnce: true,
      ),
    );

    await _notifications.show(
      _anchorNotificationId,
      'Obeisance Anchor',
      status,
      details,
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);
    _initialized = true;
  }

  void _restartTaskDebounceWindow() {
    _taskDebounceTimer?.cancel();
    _taskDebounceTimer = Timer(_taskDebounceWindow, () {
      _taskDebounceActive = false;
    });
  }

  void dispose() {
    _taskDebounceTimer?.cancel();
  }
}
