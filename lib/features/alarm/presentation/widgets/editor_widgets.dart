import 'package:flutter/material.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/time_format.dart';

/// When a recurrence stops (mirrors the domain [EndCondition] as a UI enum).
enum EndMode { never, onDate, afterCount }

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: context.mutedColor,
        ),
      ),
    );
  }
}

/// A rounded container used to group form rows.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: context.mutedColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PickerRow extends StatelessWidget {
  const PickerRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Row(
                children: [
                  Text(value, style: TextStyle(color: scheme.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20, color: context.mutedColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix = '',
    this.min = 0,
    this.max = 999,
    this.step = 1,
  });
  final String label;
  final int value;
  final String suffix;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Row(
              children: [
                IconButton(
                  onPressed: value > min
                      ? () => onChanged(value - step)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '$value${suffix.isEmpty ? '' : ' $suffix'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: value < max
                      ? () => onChanged(value + step)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WeekdaySelector extends StatelessWidget {
  const WeekdaySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  static const _labels = {
    1: 'M',
    2: 'T',
    3: 'W',
    4: 'T',
    5: 'F',
    6: 'S',
    7: 'S',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 1; d <= 7; d++)
          GestureDetector(
            onTap: () {
              final next = Set<int>.of(selected);
              next.contains(d) ? next.remove(d) : next.add(d);
              onChanged(next);
            },
            child: CircleAvatar(
              radius: 20,
              backgroundColor: selected.contains(d)
                  ? scheme.primary
                  : scheme.surface,
              child: Text(
                _labels[d]!,
                style: TextStyle(
                  color: selected.contains(d)
                      ? scheme.onPrimary
                      : context.mutedColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class IntervalRow extends StatelessWidget {
  const IntervalRow({
    super.key,
    required this.hours,
    required this.minutes,
    required this.onChanged,
  });
  final int hours;
  final int minutes;
  final void Function(int hours, int minutes) onChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Every'),
                Text(
                  '${hours}h ${minutes.toString().padLeft(2, '0')}m',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            _labelledStepper(
              'Hours',
              hours,
              0,
              72,
              (v) => onChanged(v, minutes),
            ),
            _labelledStepper(
              'Minutes',
              minutes,
              0,
              59,
              (v) => onChanged(hours, v),
              step: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelledStepper(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged, {
    int step = 1,
  }) {
    return Builder(
      builder: (context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.mutedColor)),
          Row(
            children: [
              IconButton(
                onPressed: value > min ? () => onChanged(value - step) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 40,
                child: Text('$value', textAlign: TextAlign.center),
              ),
              IconButton(
                onPressed: value < max ? () => onChanged(value + step) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OrdinalSelector extends StatelessWidget {
  const OrdinalSelector({
    super.key,
    required this.ordinal,
    required this.weekday,
    required this.onChanged,
  });
  final int ordinal;
  final int weekday;
  final void Function(int ordinal, int weekday) onChanged;

  static const _ordinals = {1: '1st', 2: '2nd', 3: '3rd', 4: '4th', 5: '5th', -1: 'Last'};
  static const _weekdays = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: ordinal,
                underline: const SizedBox.shrink(),
                items: [
                  for (final e in _ordinals.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => onChanged(v ?? ordinal, weekday),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: weekday,
                underline: const SizedBox.shrink(),
                items: [
                  for (final e in _weekdays.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => onChanged(ordinal, v ?? weekday),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShiftPatternSelector extends StatelessWidget {
  const ShiftPatternSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final ShiftPattern selected;
  final ValueChanged<ShiftPattern> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final p in ShiftPatterns.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(p),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected.id == p.id
                        ? scheme.primary
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      selected.id == p.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected.id == p.id
                          ? scheme.primary
                          : context.mutedColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.mutedColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PatternStrip(pattern: p.days),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A compact on/off strip visualising a shift cycle.
class _PatternStrip extends StatelessWidget {
  const _PatternStrip({required this.pattern});
  final List<bool> pattern;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final on in pattern)
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: on ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class TimesEditor extends StatelessWidget {
  const TimesEditor({
    super.key,
    required this.times,
    required this.onAdd,
    required this.onRemove,
    required this.onEdit,
    this.subtitle,
  });
  final List<LocalTime> times;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onEdit;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(subtitle ?? 'Times'),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            for (var i = 0; i < times.length; i++)
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => onEdit(i),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(TimeFormat.clockFromLocal(times[i])),
                    ),
                  ),
                  if (times.length > 1)
                    IconButton(
                      onPressed: () => onRemove(i),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class EndModeSelector extends StatelessWidget {
  const EndModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });
  final EndMode mode;
  final ValueChanged<EndMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<EndMode>(
      segments: const [
        ButtonSegment(value: EndMode.never, label: Text('Forever')),
        ButtonSegment(value: EndMode.onDate, label: Text('Until date')),
        ButtonSegment(value: EndMode.afterCount, label: Text('N times')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class LabelRow extends StatefulWidget {
  const LabelRow({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<LabelRow> createState() => _LabelRowState();
}

class _LabelRowState extends State<LabelRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        decoration: const InputDecoration(
          labelText: 'Label',
          border: InputBorder.none,
        ),
      ),
    );
  }
}
