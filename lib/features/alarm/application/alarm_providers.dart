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

class AlarmListController extends AsyncNotifier<List<Alarm>> {
  AlarmStore get _store => ref.read(alarmStoreProvider);
  AlarmScheduler get _scheduler => ref.read(alarmSchedulerProvider);

  @override
  Future<List<Alarm>> build() async {
    final alarms = await _store.load();
    _sortByNextFire(alarms);
    return alarms;
  }

  /// Reschedule every alarm with the OS. Call once after the scheduler is
  /// initialised at app startup.
  Future<void> resyncAllWithOs() async {
    final alarms = state.value ?? await future;
    await _scheduler.syncAll(alarms);
  }

  int _nextId(List<Alarm> alarms) {
    var max = 0;
    for (final a in alarms) {
      if (a.id > max) max = a.id;
    }
    return max + 1;
  }

  Future<Alarm> add(Alarm alarmWithoutId) async {
    final current = List<Alarm>.of(state.value ?? const []);
    final alarm = alarmWithoutId.id > 0
        ? alarmWithoutId
        : alarmWithoutId.copyWithId(_nextId(current));
    current.add(alarm);
    await _commit(current);
    await _scheduler.sync(alarm);
    return alarm;
  }

  Future<void> updateAlarm(Alarm alarm) async {
    final current = List<Alarm>.of(state.value ?? const []);
    final idx = current.indexWhere((a) => a.id == alarm.id);
    if (idx == -1) return;
    current[idx] = alarm;
    await _commit(current);
    await _scheduler.sync(alarm);
  }

  Future<void> remove(int id) async {
    final current = List<Alarm>.of(state.value ?? const []);
    current.removeWhere((a) => a.id == id);
    await _commit(current);
    await _scheduler.cancel(id);
  }

  Future<void> setEnabled(int id, bool enabled) async {
    final current = state.value;
    if (current == null) return;
    final alarm = current.firstWhere((a) => a.id == id);
    await updateAlarm(alarm.copyWith(enabled: enabled));
  }

  Future<void> _commit(List<Alarm> alarms) async {
    _sortByNextFire(alarms);
    await _store.save(alarms);
    state = AsyncData(alarms);
  }

  void _sortByNextFire(List<Alarm> alarms) {
    final now = DateTime.now();
    alarms.sort((a, b) {
      final na = a.nextFire(from: now);
      final nb = b.nextFire(from: now);
      if (na == null && nb == null) return a.id.compareTo(b.id);
      if (na == null) return 1;
      if (nb == null) return -1;
      return na.compareTo(nb);
    });
  }
}

extension on Alarm {
  Alarm copyWithId(int id) => Alarm(
    id: id,
    label: label,
    rule: rule,
    bounds: bounds,
    enabled: enabled,
    snoozeMinutes: snoozeMinutes,
    vibrate: vibrate,
    soundAsset: soundAsset,
    volume: volume,
  );
}
