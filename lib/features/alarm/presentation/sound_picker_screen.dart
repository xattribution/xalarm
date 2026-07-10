import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/ringtone_library.dart';
import '../../../services/system_sounds.dart';

/// Pick an alarm sound: favorites first, then the system default + bundled
/// tones, the user's own sounds (file / URL imports), and the device's full
/// ringtone list (copied into the library once on selection). Starring a
/// tone pins it to the Favorites section. Pops with the selected value.
class SoundPickerScreen extends ConsumerStatefulWidget {
  const SoundPickerScreen({super.key, required this.current});
  final String current;

  @override
  ConsumerState<SoundPickerScreen> createState() => _SoundPickerScreenState();
}

class _SoundPickerScreenState extends ConsumerState<SoundPickerScreen> {
  bool _busy = false;

  // --- imports ---

  Future<void> _importFile() async {
    await _run(() async {
      final result = await FilePicker.pickFiles(type: FileType.audio);
      final path = result?.files.single.path;
      if (path == null) return null;
      final tone = await ref.read(ringtoneLibraryProvider).importFile(path);
      return tone.path;
    }, errorPrefix: 'Could not import that file');
  }

  Future<void> _importUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add sound from URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/tone.mp3',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    await _run(() async {
      final tone = await ref.read(ringtoneLibraryProvider).importUrl(url);
      return tone.path;
    }, errorPrefix: 'Download failed');
  }

  /// Copy a device ringtone into the library; returns its new file path.
  Future<String?> _materialiseSystemSound(SystemSoundInfo sound) async {
    final destDir = await ref.read(ringtoneLibraryProvider).libraryDirPath();
    final path =
        await ref.read(systemSoundsProvider).copyToFile(sound, destDir);
    ref.invalidate(userTonesProvider);
    return path;
  }

  Future<void> _pickSystemSound(SystemSoundInfo sound) async {
    await _run(
      () => _materialiseSystemSound(sound),
      errorPrefix: 'Could not copy that sound',
    );
  }

  Future<void> _favoriteSystemSound(SystemSoundInfo sound) async {
    setState(() => _busy = true);
    try {
      final path = await _materialiseSystemSound(sound);
      if (path != null) {
        await ref.read(favoriteSoundsProvider.notifier).toggle(path);
      }
    } catch (e) {
      _showError('Could not copy that sound: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Run an action that produces a sound value; pop with it on success.
  Future<void> _run(
    Future<String?> Function() action, {
    required String errorPrefix,
  }) async {
    setState(() => _busy = true);
    try {
      final value = await action();
      ref.invalidate(userTonesProvider);
      if (value != null && mounted) Navigator.of(context).pop(value);
    } catch (e) {
      _showError('$errorPrefix: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(RingtoneInfo tone) async {
    await ref.read(ringtoneLibraryProvider).delete(tone.path);
    await ref.read(favoriteSoundsProvider.notifier).removePath(tone.path);
    ref.invalidate(userTonesProvider);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, maxLines: 3)),
    );
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    final userTones = ref.watch(userTonesProvider).value ?? const [];
    final favorites = ref.watch(favoriteSoundsProvider).value ?? const {};
    final systemSounds =
        ref.watch(systemSoundListProvider).value ?? const <SystemSoundInfo>[];

    // Resolve favorite paths to display tiles (skip dead file references).
    final knownTones = <String, RingtoneInfo>{
      for (final t in RingtoneLibrary.builtIn) t.path: t,
      for (final t in userTones) t.path: t,
    };
    final favoriteTones = [
      for (final path in favorites.toList()..sort())
        if (knownTones.containsKey(path)) knownTones[path]!,
    ];

    final byKind = <String, List<SystemSoundInfo>>{};
    for (final s in systemSounds) {
      byKind.putIfAbsent(s.kind, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Alarm sound')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (favoriteTones.isNotEmpty) ...[
                const _SectionLabel('Favorites'),
                _Panel(
                  child: Column(
                    children: [
                      for (final tone in favoriteTones)
                        _ToneTile(
                          tone: tone,
                          selected: widget.current == tone.path,
                          favorite: true,
                          onTap: () => Navigator.of(context).pop(tone.path),
                          onFavorite: () => ref
                              .read(favoriteSoundsProvider.notifier)
                              .toggle(tone.path),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const _SectionLabel('Tones'),
              _Panel(
                child: Column(
                  children: [
                    for (final tone in RingtoneLibrary.builtIn)
                      _ToneTile(
                        tone: tone,
                        selected: widget.current == tone.path,
                        favorite: favorites.contains(tone.path),
                        onTap: () => Navigator.of(context).pop(tone.path),
                        onFavorite: () => ref
                            .read(favoriteSoundsProvider.notifier)
                            .toggle(tone.path),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('My sounds'),
              _Panel(
                child: Column(
                  children: [
                    for (final tone in userTones)
                      _ToneTile(
                        tone: tone,
                        selected: widget.current == tone.path,
                        favorite: favorites.contains(tone.path),
                        onTap: () => Navigator.of(context).pop(tone.path),
                        onFavorite: () => ref
                            .read(favoriteSoundsProvider.notifier)
                            .toggle(tone.path),
                        onDelete: () => _delete(tone),
                      ),
                    ListTile(
                      leading: const Icon(Icons.audio_file_outlined),
                      title: const Text('Add from files'),
                      onTap: _busy ? null : _importFile,
                    ),
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: const Text('Add from URL'),
                      subtitle: Text(
                        'Downloaded once and stored — alarms ring offline.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.mutedColor,
                        ),
                      ),
                      onTap: _busy ? null : _importUrl,
                    ),
                  ],
                ),
              ),
              if (byKind.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _SectionLabel('On this device'),
                _Panel(
                  child: Column(
                    children: [
                      for (final entry in const [
                        ('alarm', 'Alarm sounds', Icons.alarm),
                        ('ringtone', 'Ringtones', Icons.ring_volume_outlined),
                        (
                          'notification',
                          'Notification sounds',
                          Icons.notifications_none,
                        ),
                      ])
                        if (byKind[entry.$1]?.isNotEmpty ?? false)
                          ExpansionTile(
                            leading: Icon(entry.$3),
                            title: Text(entry.$2),
                            subtitle: Text(
                              '${byKind[entry.$1]!.length} sounds',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.mutedColor,
                              ),
                            ),
                            children: [
                              for (final sound in byKind[entry.$1]!)
                                ListTile(
                                  dense: true,
                                  title: Text(sound.title),
                                  trailing: IconButton(
                                    tooltip: 'Copy to My sounds & favorite',
                                    icon: Icon(
                                      Icons.star_border,
                                      size: 20,
                                      color: context.mutedColor,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _favoriteSystemSound(sound),
                                  ),
                                  onTap: _busy
                                      ? null
                                      : () => _pickSystemSound(sound),
                                ),
                            ],
                          ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Picking a device sound copies it into My sounds so '
                    'alarms can always play it.',
                    style: TextStyle(fontSize: 12, color: context.mutedColor),
                  ),
                ),
              ],
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black45,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToneTile extends StatelessWidget {
  const _ToneTile({
    required this.tone,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
    this.onDelete,
  });
  final RingtoneInfo tone;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : context.mutedColor,
      ),
      title: Text(tone.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: favorite ? 'Remove favorite' : 'Favorite',
            icon: Icon(
              favorite ? Icons.star : Icons.star_border,
              size: 20,
              color: favorite ? scheme.secondary : context.mutedColor,
            ),
            onPressed: onFavorite,
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete sound',
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: context.mutedColor,
              ),
              onPressed: onDelete,
            ),
        ],
      ),
      onTap: onTap,
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
