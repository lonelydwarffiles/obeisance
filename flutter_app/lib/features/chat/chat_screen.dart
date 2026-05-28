import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/mqtt_service.dart';
import '../../core/services/telemetry_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.dommeId,
    super.key,
  });

  final String dommeId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  ProviderSubscription<AsyncValue<ChatMessage>>? _incomingSubscription;
  bool _isBooting = true;
  String? _hardwareUuid;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _incomingSubscription = ref.listenManual<AsyncValue<ChatMessage>>(
      chatMessageStreamProvider,
      (_, next) {
        next.whenData((message) {
          if (mounted) {
            setState(() {
              _messages.add(message);
            });
          }
        });
      },
    );
    _boot();
  }

  Future<void> _boot() async {
    try {
      final telemetry = await ref.read(telemetryServiceProvider).getDeviceStats();
      final hardwareUuid = telemetry['hardware_uuid'] as String;
      final mqtt = ref.read(mqttServiceProvider);
      await mqtt.initializeForAppBoot();
      await mqtt.connectForDevice(hardwareUuid: hardwareUuid);

      if (!mounted) {
        return;
      }
      setState(() {
        _hardwareUuid = hardwareUuid;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Chat service failed to connect.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBooting = false;
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    final hardwareUuid = _hardwareUuid;
    if (text.isEmpty || hardwareUuid == null) {
      return;
    }

    final outgoing = ChatMessage(
      sender: 'Sub',
      content: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(outgoing);
      _messageController.clear();
      _errorMessage = null;
    });

    try {
      await ref.read(mqttServiceProvider).publishToDommeInbox(
            dommeId: widget.dommeId,
            hardwareUuid: hardwareUuid,
            message: text,
          );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Message failed to send.';
      });
    }
  }

  @override
  void dispose() {
    _incomingSubscription?.close();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Leash Chat'),
      ),
      body: Column(
        children: [
          if (_isBooting) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isDomme = message.isDomme;
                return Align(
                  alignment: isDomme ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: isDomme ? const Color(0xFF222222) : const Color(0xFFE0B84C),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          isDomme ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                      children: [
                        Text(
                          message.sender,
                          style: TextStyle(
                            color: isDomme ? Colors.white70 : Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message.content,
                          style: TextStyle(
                            color: isDomme ? Colors.white : Colors.black,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Send a message...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isBooting ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0B84C),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
