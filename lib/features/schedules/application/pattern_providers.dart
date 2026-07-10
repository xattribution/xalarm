import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../../../core/data/json_file.dart';

/// User-created shift patterns, persisted as JSON.
final customPatternsProvider =
    AsyncNotifierProvider<CustomPatternsController, List<ShiftPattern>>(
      CustomPatternsController.new,
    );

/// Presets followed by the user's custom patterns — what pickers show.
final allPatternsProvider = Provider<List<ShiftPattern>>((ref) {
  final custom = ref.watch(customPatternsProvider).value ?? const [];
  return [...ShiftPatterns.all, ...custom];
});

class CustomPatternsController extends AsyncNotifier<List<ShiftPattern>> {
  final _file = JsonFile('custom_patterns.json');

  @override
  Future<List<ShiftPattern>> build() async {
    final raw = await _file.read();
    if (raw is! List) return [];
    return raw
        .map((e) => ShiftPattern.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> save(ShiftPattern pattern) async {
    final current = List<ShiftPattern>.of(state.value ?? const []);
    final idx = current.indexWhere((p) => p.id == pattern.id);
    if (idx == -1) {
      current.add(pattern);
    } else {
      current[idx] = pattern;
    }
    await _commit(current);
  }

  Future<void> remove(String id) async {
    final current = List<ShiftPattern>.of(state.value ?? const []);
    current.removeWhere((p) => p.id == id);
    await _commit(current);
  }

  Future<void> _commit(List<ShiftPattern> patterns) async {
    state = AsyncData(patterns);
    await _file.write(patterns.map((p) => p.toJson()).toList());
  }

  /// A unique id for a new custom pattern.
  static String newId() =>
      'custom-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
