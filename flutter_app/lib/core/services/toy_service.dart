import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:obeisance/core/services/mdm_bridge.dart';

final toyServiceProvider = Provider<ToyService>((ref) {
  final service = ToyService(mdmBridge: MdmBridge());
  ref.onDispose(service.dispose);
  return service;
});

class ToyService {
  ToyService({
    required MdmBridge mdmBridge,
    Duration checkInterval = const Duration(seconds: 10),
  })  : _mdmBridge = mdmBridge,
        _checkInterval = checkInterval;

  static const _toyMacKey = 'toy_target_mac';
  static const _proximityLockEnabledKey = 'proximity_lock_enabled';

  final MdmBridge _mdmBridge;
  final Duration _checkInterval;

  Timer? _monitorTimer;
  String? _targetMac;
  bool _proximityLockEnabled = false;
  bool _lockTriggeredForCurrentDisconnect = false;
  WebSocketChannel? _buttplugChannel;

  Future<void> startMonitorFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _targetMac = prefs.getString(_toyMacKey)?.toUpperCase();
    _proximityLockEnabled = prefs.getBool(_proximityLockEnabledKey) ?? false;
    _ensureMonitorTimer();
  }

  Future<void> setProximityLockEnabled(bool enabled, {String? targetMac}) async {
    final prefs = await SharedPreferences.getInstance();
    _proximityLockEnabled = enabled;
    await prefs.setBool(_proximityLockEnabledKey, enabled);

    if (targetMac != null && targetMac.trim().isNotEmpty) {
      _targetMac = targetMac.trim().toUpperCase();
      await prefs.setString(_toyMacKey, _targetMac!);
    } else {
      _targetMac = prefs.getString(_toyMacKey)?.toUpperCase();
    }

    if (enabled) {
      _ensureMonitorTimer();
    } else {
      _lockTriggeredForCurrentDisconnect = false;
    }
  }

  Future<void> sendVibrationPayload(String payload, {String wsUrl = 'ws://127.0.0.1:12345'}) async {
    _buttplugChannel ??= WebSocketChannel.connect(Uri.parse(wsUrl));
    _buttplugChannel!.sink.add(payload);
  }

  void _ensureMonitorTimer() {
    _monitorTimer ??= Timer.periodic(_checkInterval, (_) {
      unawaited(_checkProximity());
    });
    unawaited(_checkProximity());
  }

  Future<void> _checkProximity() async {
    if (!_proximityLockEnabled || _targetMac == null || _targetMac!.isEmpty) {
      _lockTriggeredForCurrentDisconnect = false;
      return;
    }

    final connectedDevices = await FlutterBluePlus.connectedDevices;
    final isConnected = connectedDevices.any((device) => _deviceMac(device) == _targetMac);
    if (isConnected) {
      _lockTriggeredForCurrentDisconnect = false;
      return;
    }

    if (_lockTriggeredForCurrentDisconnect) {
      return;
    }

    _lockTriggeredForCurrentDisconnect = true;
    await _mdmBridge.triggerLock();
  }

  String _deviceMac(BluetoothDevice device) {
    final remoteId = device.remoteId;
    String asString = remoteId.toString();
    try {
      final value = (remoteId as dynamic).str as String?;
      if (value != null && value.isNotEmpty) {
        asString = value;
      }
    } catch (_) {
      // Fallback to `toString()`.
    }
    return asString.toUpperCase();
  }

  void dispose() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _buttplugChannel?.sink.close();
    _buttplugChannel = null;
  }
}
