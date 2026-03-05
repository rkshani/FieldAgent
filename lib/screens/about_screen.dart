import 'package:flutter/material.dart';

import '../widgets/glass_container.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF5F2EEA), Color(0xFF2A00A2), Color(0xFF0F0C29)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: GlassContainer(
            padding: const EdgeInsets.all(24.0),
            borderRadius: BorderRadius.circular(12),
            child: const Text(
              'Premium App v1.0\n\nCreated by Your Company.\nAll rights reserved.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

