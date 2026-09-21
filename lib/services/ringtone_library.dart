import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/data/json_file.dart';
import '../core/net/url_policy.dart';

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

  /// Hard cap on a URL download so a bad link can't fill the phone.
  static const int maxDownloadBytes = 25 * 1024 * 1024;

  static bool isBuiltInAsset(String value) =>
      builtIn.any((t) => t.path == value && value != kSystemDefaultSound);

  /// True when [value] is a path inside the app's ringtone directory (the
  /// only file paths an alarm may reference).
  Future<bool> isLibraryFile(String value) async {
    if (!p.isAbsolute(value)) return false;
    final dir = await _dir();
    return p.isWithin(dir.path, p.normalize(value));
  }

  /// Null when [value] is an acceptable stored sound value, else a reason.
  Future<String?> validateSoundValue(String value) async {
    if (value == kSystemDefaultSound || isBuiltInAsset(value)) return null;
    if (await isLibraryFile(value)) return null;
    return 'soundAsset must be "system", a bundled tone, or a library file';
  }

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

  /// Absolute path of the library directory (used as the destination when
  /// the native side copies a system sound into the library).
  Future<String> libraryDirPath() async => (await _dir()).path;

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
  /// alarms must ring offline, so we never stream at ring time). HTTPS only
  /// (cleartext is allowed for LAN hosts), capped at [maxDownloadBytes].
  Future<RingtoneInfo> importUrl(String url) async {
    final problem = UrlPolicy.checkHttp(url);
    if (problem != null) throw FormatException(problem);
    final uri = Uri.parse(url.trim());
    var name = p.basename(uri.path);
    if (name.isEmpty || !_audioExtensions.contains(p.extension(name).toLowerCase())) {
      name = 'downloaded-${DateTime.now().millisecondsSinceEpoch}.mp3';
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Download failed (HTTP ${res.statusCode})');
      }
      for (final hop in res.redirects) {
        // Relative redirects stay on the same (already vetted) origin.
        if (!hop.location.hasScheme) continue;
        if (UrlPolicy.checkHttp(hop.location.toString()) != null) {
          throw const FormatException('Redirected to an insecure URL.');
        }
      }
      if (res.contentLength > maxDownloadBytes) {
        throw const FormatException('File is larger than 25 MB.');
      }
      final dir = await _dir();
      final dest = await _uniquePath(dir, name);
      final file = File(dest);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          received += chunk.length;
          if (received > maxDownloadBytes) {
            throw const FormatException('File is larger than 25 MB.');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } catch (_) {
        await sink.close();
        if (await file.exists()) await file.delete();
        rethrow;
      }
      await sink.close();
      if (received < 128) {
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

/// Favorite sound values (asset paths / file paths / 'system'), persisted so
/// preferred tones surface at the top of the sound picker.
final favoriteSoundsProvider =
    AsyncNotifierProvider<FavoriteSoundsController, Set<String>>(
      FavoriteSoundsController.new,
    );

class FavoriteSoundsController extends AsyncNotifier<Set<String>> {
  final _file = JsonFile('favorite_sounds.json');

  @override
  Future<Set<String>> build() async {
    final raw = await _file.read();
    if (raw is! List) return {};
    return raw.map((e) => e as String).toSet();
  }

  bool isFavorite(String path) => (state.value ?? const {}).contains(path);

  Future<void> toggle(String path) async {
    final next = Set<String>.of(state.value ?? const {});
    if (!next.remove(path)) next.add(path);
    state = AsyncData(next);
    await _file.write(next.toList()..sort());
  }

  Future<void> removePath(String path) async {
    final next = Set<String>.of(state.value ?? const {});
    if (next.remove(path)) {
      state = AsyncData(next);
      await _file.write(next.toList()..sort());
    }
  }
}
