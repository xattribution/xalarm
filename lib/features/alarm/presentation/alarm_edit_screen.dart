import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../../../core/constants.dart';
import '../../../core/time/time_format.dart';
import '../../../services/ringtone_library.dart';
import '../../schedules/application/pattern_providers.dart';
import '../application/alarm_providers.dart';
import '../domain/alarm.dart';
import 'sound_picker_screen.dart';
import 'widgets/editor_widgets.dart';

/// The recurrence modes the editor can produce. Kept separate from the sealed
/// [RecurrenceRule] so the UI has a stable radio-style selection.
enum RecurrenceMode {
  once('Once'),
  weekly('Weekly'),
  dailyInterval('Every N days'),
  hourlyInterval('Every N hours'),
  monthly('Monthly'),
  shift('Shift schedule');

  const RecurrenceMode(this.label);
  final String label;
}

class AlarmEditScreen extends ConsumerStatefulWidget {
  const AlarmEditScreen({super.key, this.existing});
  final Alarm? existing;

  @override
  ConsumerState<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends ConsumerState<AlarmEditScreen> {
  late RecurrenceMode _mode;
  late LocalTime _time;
  Set<int> _weekdays = {1, 2, 3, 4, 5};
  int _everyDays = 2;
  int _everyHours = 12;
  int _everyMinutes = 0;
  int _ordinal = 1;
  int _ordinalWeekday = 2;
  DateTime _anchorDate = _todayDate();
  ShiftPattern _pattern = ShiftPatterns.panama;
  List<LocalTime> _shiftTimes = [const LocalTime(6, 0)];
  Map<int, List<LocalTime>> _dayOverrides = {};

  DateTime? _startDate;
  EndMode _endMode = EndMode.never;
  DateTime _endDate = _todayDate().add(const Duration(days: 7));
  int _endCount = 7;

  late String _label;
  late int _snoozeMinutes;
  late bool _vibrate;
  late String _soundAsset;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = e?.label ?? '';
    _snoozeMinutes = e?.snoozeMinutes ?? 5;
    _vibrate = e?.vibrate ?? true;
    _soundAsset = e?.soundAsset ?? kDefaultSoundAsset;
    _time = const LocalTime(7, 0);
    _mode = RecurrenceMode.weekly;
    if (e != null) {
      _time = e.primaryTime;
      _hydrateFrom(e);
    }
  }

  void _hydrateFrom(Alarm alarm) {
    switch (alarm.rule) {
      case OneTime():
        _mode = RecurrenceMode.once;
      case Weekly(:final weekdays):
        _mode = RecurrenceMode.weekly;
        _weekdays = Set.of(weekdays);
      case DailyInterval(:final everyDays, :final anchorDate, :final times):
        _mode = RecurrenceMode.dailyInterval;
        _everyDays = everyDays;
        _anchorDate = _dateOnly(anchorDate);
        _shiftTimes = List.of(times);
      case HourlyInterval(:final every, :final anchor):
        _mode = RecurrenceMode.hourlyInterval;
        _everyHours = every.inHours;
        _everyMinutes = every.inMinutes % 60;
        _anchorDate = _dateOnly(anchor);
      case MonthlyOrdinal(:final ordinal, :final weekday):
        _mode = RecurrenceMode.monthly;
        _ordinal = ordinal;
        _ordinalWeekday = weekday;
      case ShiftCycle(
        :final anchorDate,
        :final pattern,
        :final times,
        :final perDayTimes,
      ):
        _mode = RecurrenceMode.shift;
        _anchorDate = _dateOnly(anchorDate);
        _shiftTimes = List.of(times);
        _dayOverrides = {
          for (final e in perDayTimes.entries) e.key: List.of(e.value),
        };
        final known = ref.read(allPatternsProvider);
        _pattern = known.firstWhere(
          (p) => _samePattern(p.days, pattern),
          orElse: () => ShiftPattern(
            id: 'inline-custom',
            name: 'Custom',
            description: 'Custom rotation from this alarm',
            days: pattern,
          ),
        );
    }
    final b = alarm.bounds;
    _startDate = b.startDate == null ? null : _dateOnly(b.startDate!);
    switch (b.end) {
      case NeverEnds():
        _endMode = EndMode.never;
      case EndsOnDate(:final date):
        _endMode = EndMode.onDate;
        _endDate = _dateOnly(date);
      case EndsAfterCount(:final count):
        _endMode = EndMode.afterCount;
        _endCount = count;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit alarm' : 'New alarm'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _TimeHeader(
            time: _time,
            onTap: _pickPrimaryTime,
            show: _mode != RecurrenceMode.dailyInterval &&
                _mode != RecurrenceMode.shift,
          ),
          const SizedBox(height: 8),
          const SectionHeader('Repeat'),
          _modeSelector(),
          const SizedBox(height: 12),
          ..._modeFields(),
          const SizedBox(height: 20),
          const SectionHeader('Limits'),
          _boundsFields(),
          const SizedBox(height: 20),
          const SectionHeader('Options'),
          _optionsFields(),
          if (isEditing) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete alarm'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RecurrenceMode.values.map((m) {
        return ChoiceChip(
          label: Text(m.label),
          selected: _mode == m,
          onSelected: (_) => setState(() => _mode = m),
        );
      }).toList(),
    );
  }

  List<Widget> _modeFields() {
    switch (_mode) {
      case RecurrenceMode.once:
        return [
          InfoRow(
            'Rings',
            'Next ${TimeFormat.clockFromLocal(_time)} (today or tomorrow)',
          ),
        ];
      case RecurrenceMode.weekly:
        return [
          WeekdaySelector(
            selected: _weekdays,
            onChanged: (s) => setState(() => _weekdays = s),
          ),
        ];
      case RecurrenceMode.dailyInterval:
        return [
          StepperRow(
            label: 'Every',
            value: _everyDays,
            suffix: _everyDays == 1 ? 'day' : 'days',
            min: 1,
            onChanged: (v) => setState(() => _everyDays = v),
          ),
          _anchorRow('Starting'),
          _timesEditor(),
        ];
      case RecurrenceMode.hourlyInterval:
        return [
          IntervalRow(
            hours: _everyHours,
            minutes: _everyMinutes,
            onChanged: (h, m) => setState(() {
              _everyHours = h;
              _everyMinutes = m;
            }),
          ),
          _anchorRow('First alarm'),
        ];
      case RecurrenceMode.monthly:
        return [
          OrdinalSelector(
            ordinal: _ordinal,
            weekday: _ordinalWeekday,
            onChanged: (o, w) => setState(() {
              _ordinal = o;
              _ordinalWeekday = w;
            }),
          ),
        ];
      case RecurrenceMode.shift:
        final patterns = ref.watch(allPatternsProvider);
        final knownIds = patterns.map((p) => p.id).toSet();
        return [
          ShiftPatternSelector(
            patterns: [
              // Keep an inline pattern from an existing alarm selectable even
              // though it isn't in the saved library.
              if (!knownIds.contains(_pattern.id)) _pattern,
              ...patterns,
            ],
            selected: _pattern,
            onChanged: (p) => setState(() {
              _pattern = p;
              // Drop overrides that fall outside the new cycle length or on
              // off days.
              _dayOverrides = {
                for (final e in _dayOverrides.entries)
                  if (e.key < p.days.length && p.days[e.key]) e.key: e.value,
              };
            }),
          ),
          _anchorRow('Cycle day 1'),
          _timesEditor(subtitle: 'Default start times (e.g. day & night)'),
          const SizedBox(height: 8),
          PerDayTimesEditor(
            pattern: _pattern.days,
            overrides: _dayOverrides,
            onChanged: (next) => setState(() => _dayOverrides = next),
          ),
        ];
    }
  }

  Widget _anchorRow(String label) => PickerRow(
    label: label,
    value: TimeFormat.nextFire(_anchorDate).split(' · ').first == 'Today'
        ? 'Today'
        : _formatDate(_anchorDate),
    onTap: () async {
      final picked = await _pickDate(_anchorDate);
      if (picked != null) setState(() => _anchorDate = picked);
    },
  );

  Widget _timesEditor({String? subtitle}) {
    return TimesEditor(
      times: _shiftTimes,
      subtitle: subtitle,
      onAdd: () async {
        final t = await _pickTime(const LocalTime(18, 0));
        if (t != null) setState(() => _shiftTimes = [..._shiftTimes, t]..sort());
      },
      onRemove: (i) => setState(() {
        if (_shiftTimes.length > 1) _shiftTimes.removeAt(i);
      }),
      onEdit: (i) async {
        final t = await _pickTime(_shiftTimes[i]);
        if (t != null) {
          setState(() {
            _shiftTimes[i] = t;
            _shiftTimes.sort();
          });
        }
      },
    );
  }

  Widget _boundsFields() {
    return Column(
      children: [
        SwitchRow(
          label: 'Start on a date',
          value: _startDate != null,
          onChanged: (v) => setState(
            () => _startDate = v ? _todayDate() : null,
          ),
        ),
        if (_startDate != null)
          PickerRow(
            label: 'Start date',
            value: _formatDate(_startDate!),
            onTap: () async {
              final p = await _pickDate(_startDate!);
              if (p != null) setState(() => _startDate = p);
            },
          ),
        const SizedBox(height: 4),
        EndModeSelector(
          mode: _endMode,
          onChanged: (m) => setState(() => _endMode = m),
        ),
        if (_endMode == EndMode.onDate)
          PickerRow(
            label: 'End date',
            value: _formatDate(_endDate),
            onTap: () async {
              final p = await _pickDate(_endDate);
              if (p != null) setState(() => _endDate = p);
            },
          ),
        if (_endMode == EndMode.afterCount)
          StepperRow(
            label: 'Stop after',
            value: _endCount,
            suffix: _endCount == 1 ? 'time' : 'times',
            min: 1,
            onChanged: (v) => setState(() => _endCount = v),
          ),
      ],
    );
  }

  Widget _optionsFields() {
    return Column(
      children: [
        LabelRow(
          value: _label,
          onChanged: (v) => setState(() => _label = v),
        ),
        PickerRow(
          label: 'Sound',
          value: RingtoneLibrary.displayName(_soundAsset),
          onTap: () async {
            final picked = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => SoundPickerScreen(current: _soundAsset),
              ),
            );
            if (picked != null) setState(() => _soundAsset = picked);
          },
        ),
        StepperRow(
          label: 'Snooze',
          value: _snoozeMinutes,
          suffix: 'min',
          min: 1,
          step: 1,
          onChanged: (v) => setState(() => _snoozeMinutes = v),
        ),
        SwitchRow(
          label: 'Vibrate',
          value: _vibrate,
          onChanged: (v) => setState(() => _vibrate = v),
        ),
      ],
    );
  }

  // --- pickers ---

  Future<void> _pickPrimaryTime() async {
    final t = await _pickTime(_time);
    if (t != null) setState(() => _time = t);
  }

  Future<LocalTime?> _pickTime(LocalTime initial) async {
    final res = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    return res == null ? null : LocalTime(res.hour, res.minute);
  }

  Future<DateTime?> _pickDate(DateTime initial) async {
    final now = _todayDate();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
  }

  // --- save / delete ---

  void _save() {
    final rule = _buildRule();
    final bounds = _buildBounds();
    final notifier = ref.read(alarmListProvider.notifier);
    final existing = widget.existing;
    if (existing == null) {
      notifier.add(
        Alarm(
          id: 0,
          label: _label,
          rule: rule,
          bounds: bounds,
          snoozeMinutes: _snoozeMinutes,
          vibrate: _vibrate,
          soundAsset: _soundAsset,
        ),
      );
    } else {
      notifier.updateAlarm(
        existing.copyWith(
          label: _label,
          rule: rule,
          bounds: bounds,
          snoozeMinutes: _snoozeMinutes,
          vibrate: _vibrate,
          soundAsset: _soundAsset,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  void _delete() {
    final e = widget.existing;
    if (e != null) ref.read(alarmListProvider.notifier).remove(e.id);
    Navigator.of(context).pop();
  }

  RecurrenceRule _buildRule() {
    switch (_mode) {
      case RecurrenceMode.once:
        var dt = _combine(_todayDate(), _time);
        if (!dt.isAfter(DateTime.now())) {
          dt = dt.add(const Duration(days: 1));
        }
        return OneTime(dt);
      case RecurrenceMode.weekly:
        final days = _weekdays.isEmpty ? {DateTime.now().weekday} : _weekdays;
        return Weekly(weekdays: days, time: _time);
      case RecurrenceMode.dailyInterval:
        return DailyInterval(
          everyDays: _everyDays,
          anchorDate: _anchorDate,
          times: _normalisedTimes(),
        );
      case RecurrenceMode.hourlyInterval:
        final every = Duration(hours: _everyHours, minutes: _everyMinutes);
        return HourlyInterval(
          every: every.inMinutes < 1 ? const Duration(hours: 1) : every,
          anchor: _combine(_anchorDate, _time),
        );
      case RecurrenceMode.monthly:
        return MonthlyOrdinal(
          ordinal: _ordinal,
          weekday: _ordinalWeekday,
          time: _time,
        );
      case RecurrenceMode.shift:
        return _pattern.toRule(
          anchorDate: _anchorDate,
          times: _normalisedTimes(),
          perDayTimes: {
            for (final e in _dayOverrides.entries)
              if (e.key < _pattern.days.length &&
                  _pattern.days[e.key] &&
                  e.value.isNotEmpty)
                e.key: List.of(e.value)..sort(),
          },
        );
    }
  }

  List<LocalTime> _normalisedTimes() =>
      _shiftTimes.isEmpty ? [_time] : (List.of(_shiftTimes)..sort());

  RecurrenceBounds _buildBounds() {
    final EndCondition end = switch (_endMode) {
      EndMode.never => const NeverEnds(),
      EndMode.onDate => EndsOnDate(_endDate),
      EndMode.afterCount => EndsAfterCount(_endCount),
    };
    return RecurrenceBounds(startDate: _startDate, end: end);
  }

  // --- helpers ---

  static DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _combine(DateTime date, LocalTime t) =>
      DateTime(date.year, date.month, date.day, t.hour, t.minute);

  static String _formatDate(DateTime d) => TimeFormat.clock(d) == ''
      ? ''
      : '${_months[d.month - 1]} ${d.day}, ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static bool _samePattern(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.time,
    required this.onTap,
    required this.show,
  });
  final LocalTime time;
  final VoidCallback onTap;
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox(height: 8);
    return Center(
      child: TextButton(
        onPressed: onTap,
        child: Text(
          TimeFormat.clockFromLocal(time),
          style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w200),
        ),
      ),
    );
  }
}
