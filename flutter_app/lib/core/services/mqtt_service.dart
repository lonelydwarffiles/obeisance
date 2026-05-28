import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:permission_handler/permission_handler.dart';

final mqttServiceProvider = Provider<MqttService>((ref) {
  final service = MqttService();
  ref.onDispose(service.dispose);
  return service;
});

final chatMessageStreamProvider = StreamProvider<ChatMessage>((ref) {
  return ref.watch(mqttServiceProvider).messageStream;
});

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.content,
    required this.timestamp,
  });

  final String sender;
  final String content;
  final DateTime timestamp;

  bool get isDomme => sender.toLowerCase() == 'domme';
}

class MqttService {
  MqttService()
      : _localNotifications = FlutterLocalNotificationsPlugin(),
        _updatesController = StreamController<ChatMessage>.broadcast();

  static const _androidChannelId = 'obeisance_chat_channel';
  static const _androidChannelName = 'Obeisance Chat';
  static const _androidChannelDescription = 'Chat alerts from your controller.';
  static const _defaultBrokerHost = '<backend-broker-host>';
  static const _defaultBrokerPort = 1883;

  final FlutterLocalNotificationsPlugin _localNotifications;
  final StreamController<ChatMessage> _updatesController;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _mqttSubscription;
  bool _notificationsReady = false;

  Stream<ChatMessage> get messageStream => _updatesController.stream;

  Future<void> initializeForAppBoot() async {
    await _requestPermissions();
    await _initializeLocalNotifications();
    await _configureBackgroundService();
  }

  Future<void> connectForDevice({
    required String hardwareUuid,
    String brokerHost = _defaultBrokerHost,
    int brokerPort = _defaultBrokerPort,
    String? username,
    String? password,
  }) async {
    await disconnect();

    final clientId = 'obeisance_${hardwareUuid.replaceAll('-', '').substring(0, 8)}';
    final client = MqttServerClient(brokerHost, clientId)
      ..port = brokerPort
      ..keepAlivePeriod = 30
      ..logging(on: false)
      ..secure = false
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withWillQos(MqttQos.atLeastOnce)
          .startClean();

    try {
      await client.connect(username, password);
    } catch (_) {
      client.disconnect();
      rethrow;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('MQTT connection failed');
    }

    final topic = 'cmd/device/$hardwareUuid/chat';
    client.subscribe(topic, MqttQos.atLeastOnce);
    _mqttSubscription = client.updates?.listen(_handleUpdates);
    _client = client;
  }

  Future<void> publishToDommeInbox({
    required String dommeId,
    required String hardwareUuid,
    required String message,
  }) async {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('MQTT client is not connected');
    }

    final topic = 'cmd/domme/$dommeId/inbox';
    final payload = jsonEncode({
      'sender': 'Sub',
      'hardware_uuid': hardwareUuid,
      'message': message,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    final builder = MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final publish = event.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(publish.payload.message);
      final message = _parseIncomingMessage(payload);
      _updatesController.add(message);
      unawaited(_showNotification(message));
    }
  }

  ChatMessage _parseIncomingMessage(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final sender = (decoded['sender'] as String?)?.trim();
        final message = (decoded['message'] as String?)?.trim();
        if (sender != null && sender.isNotEmpty && message != null && message.isNotEmpty) {
          return ChatMessage(
            sender: sender,
            content: message,
            timestamp: DateTime.now(),
          );
        }
      }
    } catch (_) {
      // fallback to raw payload
    }

    return ChatMessage(
      sender: 'Domme',
      content: payload,
      timestamp: DateTime.now(),
    );
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> _initializeLocalNotifications() async {
    if (_notificationsReady) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: _androidChannelDescription,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _notificationsReady = true;
  }

  Future<void> _showNotification(ChatMessage message) async {
    if (!_notificationsReady) {
      await _initializeLocalNotifications();
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'New command from ${message.sender}',
      message.content,
      details,
    );
  }

  Future<void> _configureBackgroundService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: mqttBackgroundServiceOnStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        initialNotificationTitle: 'Obeisance',
        initialNotificationContent: 'Leash service active',
        foregroundServiceNotificationId: 9021,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: mqttBackgroundServiceOnStart,
      ),
    );
    await service.startService();
  }

  Future<void> disconnect() async {
    await _mqttSubscription?.cancel();
    _mqttSubscription = null;
    _client?.disconnect();
    _client = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _updatesController.close();
  }
}

@pragma('vm:entry-point')
void mqttBackgroundServiceOnStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final mqttService = MqttService();
  await mqttService.initializeForAppBoot();

  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}
