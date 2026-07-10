import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../../core/theme/app_theme.dart';
import 'application/pattern_providers.dart';
import 'pattern_edit_screen.dart';

/// The shift-schedule library: built-in rotations plus the user's custom
/// patterns. Custom patterns can be created, edited, and deleted here, and
/// all of them are selectable when creating a shift-based alarm.
class ShiftSchedulesScreen extends ConsumerWidget {
  const ShiftSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(customPatternsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Shift schedules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PatternEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New schedule'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              'Each square is one day of the cycle — filled squares are work '
              'days. Pick any of these when creating a shift alarm.',
              style: TextStyle(color: context.mutedColor),
            ),
          ),
          if (custom.isNotEmpty) ...[
            const _SectionLabel('My schedules'),
            for (final p in custom)
              _PatternCard(
                pattern: p,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PatternEditScreen(existing: p),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
          const _SectionLabel('Built-in rotations'),
          for (final p in ShiftPatterns.all) _PatternCard(pattern: p),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
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

class _PatternCard extends StatelessWidget {
  const _PatternCard({required this.pattern, this.onTap});
  final ShiftPattern pattern;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pattern.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      Icon(Icons.edit_outlined,
                          size: 18, color: context.mutedColor),
                  ],
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
                  '${pattern.workDaysPerCycle} work days · '
                  '${pattern.cycleLength}-day cycle',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
