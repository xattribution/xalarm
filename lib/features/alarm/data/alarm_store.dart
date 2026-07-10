import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/alarm.dart';

/// Persists the alarm list as a single JSON file in the app documents dir.
/// Sufficient for v1 — no native database required.
class AlarmStore {
  static const _fileName = 'alarms.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<List<Alarm>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Alarm.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      // Corrupt or unreadable file — start clean rather than crash.
      return [];
    }
  }

  Future<void> save(List<Alarm> alarms) async {
    final file = await _file();
    final data = alarms.map((a) => a.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }
}
