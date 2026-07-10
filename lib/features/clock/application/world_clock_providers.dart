import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/json_file.dart';
import '../domain/world_city.dart';

/// Cities the user has added to the world clock, persisted as JSON.
/// Handles the legacy format (bare IANA zone-id strings).
final worldClockProvider =
    AsyncNotifierProvider<WorldClockController, List<WorldCity>>(
      WorldClockController.new,
    );

class WorldClockController extends AsyncNotifier<List<WorldCity>> {
  final _file = JsonFile('world_clock.json');

  @override
  Future<List<WorldCity>> build() async {
    final raw = await _file.read();
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is String)
          WorldCity.fromZoneId(e) // legacy entry
        else if (e is Map)
          WorldCity.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> add(WorldCity city) async {
    final current = List<WorldCity>.of(state.value ?? const []);
    if (current.any((c) => c.name == city.name && c.tz == city.tz)) return;
    current.add(city);
    await _commit(current);
  }

  Future<void> remove(WorldCity city) async {
    final current = List<WorldCity>.of(state.value ?? const [])
      ..removeWhere((c) => c.name == city.name && c.tz == city.tz);
    await _commit(current);
  }

  Future<void> _commit(List<WorldCity> cities) async {
    state = AsyncData(cities);
    await _file.write([for (final c in cities) c.toJson()]);
  }
}
