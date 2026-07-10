import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Sentinel value for [Alarm.soundAsset] meaning "use the device's default
/// alarm sound" (the alarm package plays the system sound when the audio
/// path is null).
const String kSystemDefaultSound = 'system';

class RingtoneInfo {
  final String path; // asset path, absolute file path, or kSystemDefaultSound
  final String name;
  final bool builtIn;
  const RingtoneInfo({
    required this.path,
    required this.name,
    required this.builtIn,
  });
}

/// Built-in tones bundled with the app plus the user's imported sounds
/// (files picked from the device or downloaded from a URL, stored under
/// the app's documents/ringtones directory).
class RingtoneLibrary {
  static const List<RingtoneInfo> builtIn = [
    RingtoneInfo(path: kSystemDefaultSound, name: 'System default', builtIn: true),
    RingtoneInfo(path: 'assets/sounds/alarm.wav', name: 'Classic', builtIn: true),
    RingtoneInfo(path: 'assets/sounds/chime.wav', name: 'Chime', builtIn: true),
    RingtoneInfo(path: 'assets/sounds/digital.wav', name: 'Digital', builtIn: true),
    RingtoneInfo(path: 'assets/sounds/gentle.wav', name: 'Gentle', builtIn: true),
    RingtoneInfo(path: 'assets/sounds/pulse.wav', name: 'Pulse', builtIn: true),
  ];

  static const _audioExtensions = {
    '.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac', '.opus',
  };

  /// Human-readable name for any stored sound value.
  static String displayName(String soundAsset) {
    for (final tone in builtIn) {
      if (tone.path == soundAsset) return tone.name;
    }
    return _pretty(p.basenameWithoutExtension(soundAsset));
  }

  static String _pretty(String base) => base
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim();

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'ringtones'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<RingtoneInfo>> userTones() async {
    final dir = await _dir();
    final tones = <RingtoneInfo>[];
    await for (final entry in dir.list()) {
      if (entry is File &&
          _audioExtensions.contains(p.extension(entry.path).toLowerCase())) {
        tones.add(RingtoneInfo(
          path: entry.path,
          name: _pretty(p.basenameWithoutExtension(entry.path)),
          builtIn: false,
        ));
      }
    }
    tones.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return tones;
  }

  /// Copy a picked file into the library. Returns the stored tone.
  Future<RingtoneInfo> importFile(String sourcePath) async {
    final ext = p.extension(sourcePath).toLowerCase();
    if (!_audioExtensions.contains(ext)) {
      throw const FormatException('Not a supported audio file.');
    }
    final dir = await _dir();
    final dest = await _uniquePath(dir, p.basename(sourcePath));
    await File(sourcePath).copy(dest);
    return RingtoneInfo(
      path: dest,
      name: _pretty(p.basenameWithoutExtension(dest)),
      builtIn: false,
    );
  }

  /// Download an audio file from a URL into the library (one-time download —
  /// alarms must ring offline, so we never stream at ring time).
  Future<RingtoneInfo> importUrl(String url) async {
    final uri = Uri.parse(url.trim());
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw const FormatException('URL must start with http:// or https://');
    }
    var name = p.basename(uri.path);
    if (name.isEmpty || !_audioExtensions.contains(p.extension(name).toLowerCase())) {
      name = 'downloaded-${DateTime.now().millisecondsSinceEpoch}.mp3';
    }

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Download failed (HTTP ${res.statusCode})');
      }
      final dir = await _dir();
      final dest = await _uniquePath(dir, name);
      final sink = File(dest).openWrite();
      await res.pipe(sink);
      final file = File(dest);
      if (await file.length() < 128) {
        await file.delete();
        throw const FormatException('Downloaded file is empty.');
      }
      return RingtoneInfo(
        path: dest,
        name: _pretty(p.basenameWithoutExtension(dest)),
        builtIn: false,
      );
    } finally {
      client.close();
    }
  }

  Future<void> delete(String path) async {
    final dir = await _dir();
    // Only ever delete files inside the library directory.
    if (!p.isWithin(dir.path, path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<String> _uniquePath(Directory dir, String fileName) async {
    var candidate = p.join(dir.path, fileName);
    var n = 1;
    while (await File(candidate).exists()) {
      final base = p.basenameWithoutExtension(fileName);
      final ext = p.extension(fileName);
      candidate = p.join(dir.path, '$base-$n$ext');
      n++;
    }
    return candidate;
  }
}

final ringtoneLibraryProvider = Provider<RingtoneLibrary>(
  (ref) => RingtoneLibrary(),
);

/// The user's imported sounds; invalidate after import/delete.
final userTonesProvider = FutureProvider<List<RingtoneInfo>>(
  (ref) => ref.watch(ringtoneLibraryProvider).userTones(),
);
