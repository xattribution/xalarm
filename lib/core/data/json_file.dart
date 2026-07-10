import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Minimal JSON-file persistence used by all the app's stores
/// (alarms, settings, custom patterns, world-clock cities).
class JsonFile {
  JsonFile(this.fileName);
  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, fileName));
  }

  /// Reads and decodes the file, or returns null if missing/corrupt.
  Future<Object?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    } catch (_) {
      return null; // corrupt file — callers start clean rather than crash
    }
  }

  Future<void> write(Object data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data));
  }
}
