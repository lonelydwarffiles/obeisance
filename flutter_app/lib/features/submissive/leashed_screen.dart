import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LeashedScreen extends StatelessWidget {
  const LeashedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Leashed'),
      ),
      body: const Center(
        child: Text(
          'Leash active.',
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/chat'),
        backgroundColor: const Color(0xFFE0B84C),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Chat'),
      ),
    );
  }
}
