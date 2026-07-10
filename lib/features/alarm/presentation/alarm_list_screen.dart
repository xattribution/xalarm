import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/time/time_format.dart';
import '../application/alarm_providers.dart';
import '../domain/alarm.dart';
import '../domain/recurrence_summary.dart';
import 'alarm_edit_screen.dart';

class AlarmListScreen extends ConsumerWidget {
  const AlarmListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmListProvider);

    return alarmsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load alarms:\n$e')),
      data: (alarms) {
        if (alarms.isEmpty) return const _EmptyState();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: alarms.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _AlarmCard(alarm: alarms[i]),
        );
      },
    );
  }
}

class _AlarmCard extends ConsumerWidget {
  const _AlarmCard({required this.alarm});
  final Alarm alarm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final next = alarm.nextFire();
    final muted = context.mutedColor;
    final active = alarm.enabled;

    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      onDismissed: (_) => ref.read(alarmListProvider.notifier).remove(alarm.id),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AlarmEditScreen(existing: alarm),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TimeFormat.clockFromLocal(alarm.primaryTime),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w300,
                          color: active ? scheme.onSurface : muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (alarm.label.isNotEmpty)
                        Text(
                          alarm.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: active ? scheme.onSurface : muted,
                          ),
                        ),
                      Text(
                        RecurrenceSummary.describe(alarm.rule, alarm.bounds),
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active
                            ? (next != null
                                  ? 'Next: ${TimeFormat.nextFire(next)}'
                                  : 'No upcoming alarms')
                            : 'Off',
                        style: TextStyle(
                          fontSize: 12,
                          color: active ? scheme.secondary : muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: alarm.enabled,
                  onChanged: (v) => ref
                      .read(alarmListProvider.notifier)
                      .setEnabled(alarm.id, v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedColor;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_add_outlined, size: 64, color: muted),
          const SizedBox(height: 16),
          const Text(
            'No alarms yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tap + to add a standard alarm or a shift-based schedule.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
