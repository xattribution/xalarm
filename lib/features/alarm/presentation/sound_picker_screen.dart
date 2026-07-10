import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/ringtone_library.dart';

/// Pick an alarm sound: system default, a bundled tone, or the user's own
/// sounds (imported from a file on the device or downloaded from a URL).
/// Pops with the selected sound value (asset path / file path / 'system').
class SoundPickerScreen extends ConsumerStatefulWidget {
  const SoundPickerScreen({super.key, required this.current});
  final String current;

  @override
  ConsumerState<SoundPickerScreen> createState() => _SoundPickerScreenState();
}

class _SoundPickerScreenState extends ConsumerState<SoundPickerScreen> {
  bool _busy = false;

  Future<void> _importFile() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.pickFiles(type: FileType.audio);
      final path = result?.files.single.path;
      if (path == null) return;
      final tone =
          await ref.read(ringtoneLibraryProvider).importFile(path);
      ref.invalidate(userTonesProvider);
      if (mounted) Navigator.of(context).pop(tone.path);
    } catch (e) {
      _showError('Could not import that file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

    setState(() => _busy = true);
    try {
      final tone = await ref.read(ringtoneLibraryProvider).importUrl(url);
      ref.invalidate(userTonesProvider);
      if (mounted) Navigator.of(context).pop(tone.path);
    } catch (e) {
      _showError('Download failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(RingtoneInfo tone) async {
    await ref.read(ringtoneLibraryProvider).delete(tone.path);
    ref.invalidate(userTonesProvider);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, maxLines: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userTones = ref.watch(userTonesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Alarm sound')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const _SectionLabel('Tones'),
              _Panel(
                child: Column(
                  children: [
                    for (final tone in RingtoneLibrary.builtIn)
                      _ToneTile(
                        tone: tone,
                        selected: widget.current == tone.path,
                        onTap: () => Navigator.of(context).pop(tone.path),
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
                        onTap: () => Navigator.of(context).pop(tone.path),
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
    required this.onTap,
    this.onDelete,
  });
  final RingtoneInfo tone;
  final bool selected;
  final VoidCallback onTap;
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
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Delete sound',
              icon: Icon(Icons.delete_outline,
                  size: 20, color: context.mutedColor),
              onPressed: onDelete,
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
