import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../core/data/json_file.dart';
import '../features/alarm/application/alarm_providers.dart';
import '../features/alarm/domain/alarm.dart';
import '../features/clock/application/world_clock_providers.dart';

/// Pushes a snapshot of widget-relevant data (next alarm, 7-day shift strip,
/// world-clock zones, stopwatch state) to the native side, which stores it
/// and refreshes the home-screen widgets.
class WidgetSyncService {
  WidgetSyncService(this._ref);
  final Ref _ref;

  static const _channel = MethodChannel('xalarm/system_sounds');

  Future<void> push() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final payload = await _buildPayload();
      await _channel.invokeMethod('syncWidgets', {
        'json': jsonEncode(payload),
      });
    } catch (e) {
      debugPrint('Widget sync failed: $e');
    }
  }

  Future<Map<String, dynamic>> _buildPayload() async {
    final alarms = await _ref.read(alarmListProvider.future);
    final zones = await _ref.read(worldClockProvider.future);
    final stopwatch = await JsonFile('stopwatch.json').read();

    // Next alarm across all enabled alarms.
    final now = DateTime.now();
    DateTime? next;
    Alarm? nextAlarm;
    for (final a in alarms) {
      final f = a.nextFire(from: now);
      if (f != null && (next == null || f.isBefore(next))) {
        next = f;
        nextAlarm = a;
      }
    }

    // 7-day shift strip from the first enabled shift alarm.
    List<Map<String, dynamic>>? shiftDays;
    String? shiftLabel;
    for (final a in alarms) {
      if (!a.enabled) continue;
      final rule = a.rule;
      if (rule is ShiftCycle) {
        shiftDays = _shiftWeek(rule, now);
        shiftLabel = a.label.isEmpty ? 'Shift' : a.label;
        break;
      }
    }

    return {
      'nextAlarmAtMs': next?.millisecondsSinceEpoch,
      'nextAlarmLabel': nextAlarm?.label ?? '',
      'shiftLabel': shiftLabel,
      'shiftDays': shiftDays,
      'zones': [
        for (final c in zones) {'city': c.name, 'tz': c.tz},
      ],
      'stopwatch': stopwatch is Map
          ? Map<String, dynamic>.from(stopwatch)
          : null,
    };
  }

  /// On/off flags for today + the next 6 days of a shift cycle.
  static List<Map<String, dynamic>> _shiftWeek(ShiftCycle rule, DateTime now) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final anchor = DateTime.utc(
      rule.anchorDate.year,
      rule.anchorDate.month,
      rule.anchorDate.day,
    );
    final len = rule.pattern.length;
    return [
      for (var i = 0; i < 7; i++)
        () {
          final day = DateTime(now.year, now.month, now.day + i);
          final utcDay = DateTime.utc(day.year, day.month, day.day);
          final idx = utcDay.difference(anchor).inDays % len;
          return {
            'letter': letters[day.weekday - 1],
            'on': rule.pattern[idx < 0 ? idx + len : idx],
            'today': i == 0,
          };
        }(),
    ];
  }
}

final widgetSyncProvider = Provider<WidgetSyncService>(
  (ref) => WidgetSyncService(ref),
);
