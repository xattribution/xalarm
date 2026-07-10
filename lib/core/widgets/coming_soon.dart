import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A clean placeholder for features arriving in a later milestone.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
