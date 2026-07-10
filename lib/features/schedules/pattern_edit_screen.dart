import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../../core/theme/app_theme.dart';
import '../alarm/presentation/widgets/editor_widgets.dart';
import 'application/pattern_providers.dart';

/// Create or edit a custom rotating shift pattern: name it, set the cycle
/// length, and tap days to toggle work/off.
class PatternEditScreen extends ConsumerStatefulWidget {
  const PatternEditScreen({super.key, this.existing});
  final ShiftPattern? existing;

  @override
  ConsumerState<PatternEditScreen> createState() => _PatternEditScreenState();
}

class _PatternEditScreenState extends ConsumerState<PatternEditScreen> {
  late final TextEditingController _name;
  late List<bool> _days;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _days = List.of(
      widget.existing?.days ?? [true, true, true, true, false, false],
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setLength(int length) {
    setState(() {
      if (length > _days.length) {
        _days = [..._days, ...List.filled(length - _days.length, false)];
      } else {
        _days = _days.sublist(0, length);
      }
    });
  }

  Future<void> _save() async {
    final workDays = _days.where((d) => d).length;
    if (workDays == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mark at least one day as a work day.')),
      );
      return;
    }
    final name = _name.text.trim().isEmpty ? 'My schedule' : _name.text.trim();
    final pattern = ShiftPattern(
      id: widget.existing?.id ?? CustomPatternsController.newId(),
      name: name,
      description:
          '$workDays work days in a ${_days.length}-day cycle · custom',
      days: List.of(_days),
    );
    await ref.read(customPatternsProvider.notifier).save(pattern);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit schedule' : 'New schedule'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Schedule name',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          StepperRow(
            label: 'Cycle length',
            value: _days.length,
            suffix: 'days',
            min: 2,
            max: 42,
            onChanged: _setLength,
          ),
          const SizedBox(height: 20),
          const SectionHeader('Tap days to toggle work / off'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _days.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _days[i] = !_days[i]),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _days[i]
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _days[i] ? scheme.onPrimary : context.mutedColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_days.where((d) => d).length} work days per '
            '${_days.length}-day cycle. Day 1 lines up with the '
            '“cycle day 1” date you pick when creating an alarm.',
            style: TextStyle(fontSize: 13, color: context.mutedColor),
          ),
          if (isEditing) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () async {
                await ref
                    .read(customPatternsProvider.notifier)
                    .remove(widget.existing!.id);
                if (context.mounted) Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete schedule'),
            ),
          ],
        ],
      ),
    );
  }
}
