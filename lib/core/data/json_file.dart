import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Minimal JSON-file persistence used by all the app's stores
/// (alarms, settings, custom patterns, world-clock cities).
///
/// Writes are crash-safe: the new content goes to a temp file first, the
/// previous file is kept as `.bak`, and only then is the temp file renamed
/// into place. A read that finds the main file missing or corrupt falls back
/// to the backup instead of silently starting from nothing.
class JsonFile {
  JsonFile(this.fileName);
  final String fileName;

  Future<File> _file([String suffix = '']) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, '$fileName$suffix'));
  }

  /// Reads and decodes the file (or its backup), or returns null if neither
  /// exists or parses.
  Future<Object?> read() async {
    final main = await _read(await _file());
    if (main != null) return main;
    return _read(await _file('.bak'));
  }

  Future<Object?> _read(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    } catch (e) {
      debugPrint('JsonFile: ${file.path} unreadable: $e');
      return null;
    }
  }

  Future<void> write(Object data) async {
    final target = await _file();
    final backup = await _file('.bak');
    final tmp = await _file('.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    if (await target.exists()) {
      await target.rename(backup.path);
    }
    await tmp.rename(target.path);
  }
}
