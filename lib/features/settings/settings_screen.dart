import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'APPEARANCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (m) {
              if (m != null) {
                ref.read(themeModeProvider.notifier).set(m);
              }
            },
            child: Column(
              children: const [
                _ThemeTile(mode: ThemeMode.dark, label: 'Dark'),
                _ThemeTile(mode: ThemeMode.light, label: 'Light'),
                _ThemeTile(mode: ThemeMode.system, label: 'System'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.mode, required this.label});
  final ThemeMode mode;
  final String label;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ThemeMode>(value: mode, title: Text(label));
  }
}
