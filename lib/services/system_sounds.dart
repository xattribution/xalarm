import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A sound installed on the device (system alarm / ringtone / notification),
/// referenced by its content:// URI until it is copied into the library.
class SystemSoundInfo {
  final String title;
  final String uri;
  final String kind; // alarm | ringtone | notification
  const SystemSoundInfo({
    required this.title,
    required this.uri,
    required this.kind,
  });
}

/// Bridge to the Android RingtoneManager (see MainActivity.kt). The alarm
/// player needs real file paths, so picking a system sound copies it into
/// the app's ringtone library once. Also drives the native MediaPlayer for
/// in-picker sound previews.
class SystemSounds {
  static const _channel = MethodChannel('xalarm/system_sounds');

  SystemSounds() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'previewEnded') {
        onPreviewEnded?.call();
      }
    });
  }

  /// Set by the sound picker so it can reset its play indicator when a
  /// preview finishes on its own (or is cut off by the OS).
  VoidCallback? onPreviewEnded;

  /// Preview any sound source: 'system', an asset path, a content:// URI,
  /// or an absolute file path. A new preview replaces the previous one.
  Future<void> preview(String source) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('preview', {'source': source});
    } on PlatformException catch (e) {
      debugPrint('Preview failed: ${e.message}');
      onPreviewEnded?.call();
    }
  }

  Future<void> stopPreview() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('stopPreview');
    } on PlatformException {
      // Already stopped — nothing to do.
    }
  }

  Future<List<SystemSoundInfo>> list() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    try {
      final raw = await _channel.invokeListMethod<Map>('list');
      return [
        for (final entry in raw ?? const <Map>[])
          SystemSoundInfo(
            title: entry['title'] as String? ?? 'Unknown',
            uri: entry['uri'] as String? ?? '',
            kind: entry['kind'] as String? ?? 'ringtone',
          ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Copy [sound] into [destDir]; returns the created file path.
  Future<String> copyToFile(SystemSoundInfo sound, String destDir) async {
    final path = await _channel.invokeMethod<String>('copyToFile', {
      'uri': sound.uri,
      'destDir': destDir,
      'title': sound.title,
    });
    if (path == null) throw StateError('Copy returned no path');
    return path;
  }
}

final systemSoundsProvider = Provider<SystemSounds>((ref) => SystemSounds());

/// The device's sound list, grouped by kind, fetched once per session.
final systemSoundListProvider = FutureProvider<List<SystemSoundInfo>>(
  (ref) => ref.watch(systemSoundsProvider).list(),
);
