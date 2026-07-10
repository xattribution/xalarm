import 'package:flutter/material.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../../core/theme/app_theme.dart';

/// A reference library of the built-in rotating-shift templates. Users pick one
/// of these when creating a shift-based alarm on the Alarm tab.
class ShiftSchedulesScreen extends StatelessWidget {
  const ShiftSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shift schedules')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              'Rotating patterns you can attach to an alarm. Each square is one '
              'day of the cycle — filled squares are work days.',
              style: TextStyle(color: context.mutedColor),
            ),
          ),
          for (final p in ShiftPatterns.all) _PatternCard(pattern: p),
        ],
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({required this.pattern});
  final ShiftPattern pattern;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pattern.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            pattern.description,
            style: TextStyle(fontSize: 13, color: context.mutedColor),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final on in pattern.days)
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: on
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${pattern.workDaysPerCycle} work days · ${pattern.cycleLength}-day cycle',
            style: TextStyle(
              fontSize: 12,
              color: scheme.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
