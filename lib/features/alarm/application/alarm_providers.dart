import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/alarm_scheduler.dart';
import '../data/alarm_store.dart';
import '../domain/alarm.dart';

final alarmStoreProvider = Provider<AlarmStore>((ref) => AlarmStore());

final alarmSchedulerProvider = Provider<AlarmScheduler>(
  (ref) => AlarmScheduler(),
);

/// The reactive list of alarms, backed by the JSON store and kept in sync with
/// the OS scheduler on every mutation.
final alarmListProvider =
    AsyncNotifierProvider<AlarmListController, List<Alarm>>(
      AlarmListController.new,
    );

/// Thrown by mutations that receive an alarm [Alarm.validate] rejects.
class InvalidAlarmException implements Exception {
  const InvalidAlarmException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AlarmListController extends AsyncNotifier<List<Alarm>> {
  AlarmStore get _store => ref.read(alarmStoreProvider);
  AlarmScheduler get _scheduler => ref.read(alarmSchedulerProvider);

  /// Mutations run one at a time so concurrent callers (UI + local API)
  /// can't read the same snapshot and hand out duplicate ids.
  Future<void> _queue = Future.value();

  @override
  Future<List<Alarm>> build() async {
    final alarms = await _store.load();
    _sortByNextFire(alarms);
    return alarms;
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final run = _queue.then((_) => op());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Reschedule every alarm with the OS. Call once after the scheduler is
  /// initialised at app startup.
  Future<void> resyncAllWithOs() => _serial(() async {
    final alarms = state.value ?? await future;
    await _scheduler.syncAll(alarms);
  });

  int _nextId(List<Alarm> alarms) {
    var max = 0;
    for (final a in alarms) {
      if (a.id > max) max = a.id;
    }
    return max + 1;
  }

  Alarm _checked(Alarm alarm) {
    final problem = alarm.validate();
    if (problem != null) throw InvalidAlarmException(problem);
    return alarm.normalized();
  }

  Future<Alarm> add(Alarm alarmWithoutId) => _serial(() async {
    final current = List<Alarm>.of(state.value ?? await future);
    final alarm = _checked(alarmWithoutId).copyWith(id: _nextId(current));
    current.add(alarm);
    await _commit(current);
    await _scheduler.sync(alarm);
    return alarm;
  });

  Future<void> updateAlarm(Alarm alarm) => _serial(() async {
    final current = List<Alarm>.of(state.value ?? await future);
    final idx = current.indexWhere((a) => a.id == alarm.id);
    if (idx == -1) return;
    final next = _checked(alarm);
    current[idx] = next;
    await _commit(current);
    await _scheduler.sync(next);
  });

  Future<void> remove(int id) => _serial(() async {
    final current = List<Alarm>.of(state.value ?? await future);
    current.removeWhere((a) => a.id == id);
    await _commit(current);
    await _scheduler.cancel(id, includeSnooze: true);
  });

  Future<void> setEnabled(int id, bool enabled) async {
    final alarm = _find(id);
    if (alarm == null) return;
    await updateAlarm(alarm.copyWith(enabled: enabled));
  }

  /// Every alarm using [oldSound] switches to [newSound] (used when a
  /// library tone is deleted so nothing points at a missing file).
  Future<void> replaceSound(String oldSound, String newSound) =>
      _serial(() async {
        final current = List<Alarm>.of(state.value ?? await future);
        final changed = <Alarm>[];
        for (var i = 0; i < current.length; i++) {
          if (current[i].soundAsset == oldSound) {
            current[i] = current[i].copyWith(soundAsset: newSound);
            changed.add(current[i]);
          }
        }
        if (changed.isEmpty) return;
        await _commit(current);
        for (final a in changed) {
          await _scheduler.sync(a);
        }
      });

  /// A native alarm with [nativeId] just stopped ringing (Stop button in the
  /// app or the notification, or a snooze). Tops the owning alarm's horizon
  /// back up and switches it off once its series is exhausted (one-time
  /// alarms, "until a date", "after N times").
  Future<void> onNativeAlarmStopped(int nativeId) => _serial(() async {
    final id = _scheduler.alarmIdForNative(nativeId);
    if (id == null) return;
    final alarm = _find(id);
    if (alarm == null || !alarm.enabled) return;
    if (alarm.nextFire() == null) {
      final current = List<Alarm>.of(state.value ?? const []);
      final idx = current.indexWhere((a) => a.id == id);
      if (idx != -1) {
        current[idx] = alarm.copyWith(enabled: false);
        await _commit(current);
      }
      // Leave an active snooze alone; only the occurrence slots are gone.
      await _scheduler.cancel(id);
      return;
    }
    await _scheduler.sync(alarm);
  });

  Alarm? _find(int id) {
    for (final a in state.value ?? const <Alarm>[]) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _commit(List<Alarm> alarms) async {
    _sortByNextFire(alarms);
    try {
      await _store.save(alarms);
    } catch (e) {
      debugPrint('AlarmStore save failed: $e');
      rethrow;
    }
    state = AsyncData(alarms);
  }

  void _sortByNextFire(List<Alarm> alarms) {
    final now = DateTime.now();
    final next = {for (final a in alarms) a.id: a.nextFire(from: now)};
    alarms.sort((a, b) {
      final na = next[a.id];
      final nb = next[b.id];
      if (na == null && nb == null) return a.id.compareTo(b.id);
      if (na == null) return 1;
      if (nb == null) return -1;
      return na.compareTo(nb);
    });
  }
}
