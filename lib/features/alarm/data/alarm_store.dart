import 'package:flutter/foundation.dart';

import '../../../core/data/json_file.dart';
import '../domain/alarm.dart';

/// Persists the alarm list as a single JSON file in the app documents dir.
/// Entries that fail to parse or validate are skipped individually — one
/// bad record must never wipe the whole list.
class AlarmStore {
  final _file = JsonFile('alarms.json');

  Future<List<Alarm>> load() async {
    final raw = await _file.read();
    if (raw is! List) return [];
    final alarms = <Alarm>[];
    for (final entry in raw) {
      try {
        final alarm = Alarm.fromJson(Map<String, dynamic>.from(entry as Map));
        final problem = alarm.validate();
        if (problem != null) {
          debugPrint('AlarmStore: skipping alarm ${alarm.id}: $problem');
          continue;
        }
        alarms.add(alarm);
      } catch (e) {
        debugPrint('AlarmStore: skipping unreadable alarm entry: $e');
      }
    }
    return alarms;
  }

  Future<void> save(List<Alarm> alarms) =>
      _file.write(alarms.map((a) => a.toJson()).toList());
}
