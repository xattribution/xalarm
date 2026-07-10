import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/build_info.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/system_sounds.dart';
import '../../services/update_checker.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checking = false;
  UpdateCheckResult? _lastCheck;
  String? _checkError;

  Future<void> _checkForUpdates() async {
    final settings =
        ref.read(settingsProvider).value ?? const AppSettings();
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final result = await ref
          .read(updateCheckerProvider)
          .check(settings.updateUrl);
      setState(() => _lastCheck = result);
    } catch (e) {
      setState(() {
        _lastCheck = null;
        _checkError = 'Could not reach the update server: $e';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadUpdate() async {
    final apkUrl = _lastCheck?.apkUrl;
    if (apkUrl == null) return;
    try {
      await ref.read(systemSoundsProvider).openUrl(apkUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the download: $e')),
        );
      }
    }
  }

  Future<void> _editUpdateUrl(String current) async {
    final controller = TextEditingController(text: current);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update server'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: kDefaultUpdateUrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (url != null) {
      await ref.read(settingsProvider.notifier).setUpdateUrl(url);
      setState(() => _lastCheck = null);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 24),
          const _SectionLabel('About & updates'),
          _Panel(
            child: Column(
              children: [
                ListTile(
                  title: const Text('This build'),
                  subtitle: Text(
                    '${BuildInfo.commit} · ${BuildInfo.date}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.mutedColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Update server'),
                  subtitle: Text(
                    settings.updateUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12.5, color: context.mutedColor),
                  ),
                  trailing: Icon(Icons.edit_outlined,
                      size: 18, color: context.mutedColor),
                  onTap: () => _editUpdateUrl(settings.updateUrl),
                ),
                const Divider(height: 1),
                if (_lastCheck?.updateAvailable ?? false)
                  ListTile(
                    leading: Icon(Icons.system_update, color: scheme.primary),
                    title: const Text('Update available'),
                    subtitle: Text(
                      'Build ${_lastCheck!.remoteCommit} · '
                      '${_lastCheck!.remoteDate}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.mutedColor,
                      ),
                    ),
                    trailing: FilledButton(
                      onPressed: _downloadUpdate,
                      child: const Text('Download'),
                    ),
                  )
                else
                  ListTile(
                    leading: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _lastCheck != null
                                ? Icons.check_circle_outline
                                : Icons.refresh,
                            color: _lastCheck != null
                                ? scheme.secondary
                                : context.mutedColor,
                          ),
                    title: Text(
                      _checking
                          ? 'Checking…'
                          : _checkError != null
                              ? 'Check failed'
                              : _lastCheck != null
                                  ? 'Up to date'
                                  : 'Check for updates',
                    ),
                    subtitle: _checkError == null
                        ? null
                        : Text(
                            _checkError!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.mutedColor,
                            ),
                          ),
                    onTap: _checking ? null : _checkForUpdates,
                  ),
                if (_lastCheck?.updateAvailable ?? false)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'The APK downloads in your browser; open it when '
                      'finished to install over this version. Alarms and '
                      'settings are kept.',
                      style:
                          TextStyle(fontSize: 12, color: context.mutedColor),
                    ),
                  ),
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
