import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final controller = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          const _SectionLabel('Appearance'),
          _Panel(
            child: RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (m) {
                if (m != null) controller.setThemeMode(m);
              },
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    title: Text('Dark'),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    title: Text('Light'),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    title: Text('System'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('Home Assistant'),
          _Panel(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Local API'),
                  subtitle: Text(
                    'Lets Home Assistant read and control alarms over '
                    'your network while the app is running.',
                    style:
                        TextStyle(fontSize: 12.5, color: context.mutedColor),
                  ),
                  value: settings.apiEnabled,
                  onChanged: controller.setApiEnabled,
                ),
                if (settings.apiEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Port'),
                    trailing: SizedBox(
                      width: 90,
                      child: TextFormField(
                        key: ValueKey('port-${settings.apiPort}'),
                        initialValue: '${settings.apiPort}',
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                        style: TextStyle(color: scheme.primary, fontSize: 16),
                        onFieldSubmitted: (v) {
                          final port = int.tryParse(v);
                          if (port != null) controller.setApiPort(port);
                        },
                      ),
                    ),
                  ),
                  ListTile(
                    title: const Text('Access token'),
                    subtitle: Text(
                      settings.apiToken,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.mutedColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Copy token',
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: settings.apiToken),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Token copied'),
                                ),
                              );
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Generate new token',
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: controller.regenerateToken,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Text(
                      'Base URL: http://<this-phone-ip>:${settings.apiPort}/api\n'
                      'Send the token as “Authorization: Bearer <token>”. '
                      'Setup examples live in docs/home_assistant.md in the '
                      'project repo.',
                      style:
                          TextStyle(fontSize: 12, color: context.mutedColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: context.mutedColor,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
