import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/json_file.dart';

/// IANA zone ids the user has added to the world clock, persisted as JSON.
final worldClockProvider =
    AsyncNotifierProvider<WorldClockController, List<String>>(
      WorldClockController.new,
    );

class WorldClockController extends AsyncNotifier<List<String>> {
  final _file = JsonFile('world_clock.json');

  @override
  Future<List<String>> build() async {
    final raw = await _file.read();
    if (raw is! List) return [];
    return raw.map((e) => e as String).toList();
  }

  Future<void> add(String zoneId) async {
    final current = List<String>.of(state.value ?? const []);
    if (current.contains(zoneId)) return;
    current.add(zoneId);
    await _commit(current);
  }

  Future<void> remove(String zoneId) async {
    final current = List<String>.of(state.value ?? const [])..remove(zoneId);
    await _commit(current);
  }

  Future<void> _commit(List<String> zones) async {
    state = AsyncData(zones);
    await _file.write(zones);
  }
}
