import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/theme/app_theme.dart';
import '../../core/time/time_format.dart';
import 'application/world_clock_providers.dart';

/// The Clock tab: a live local clock plus a comparable list of world cities.
class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zones = ref.watch(worldClockProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
      children: [
        Center(
          child: Column(
            children: [
              Text(
                TimeFormat.clock(_now),
                style: TextStyle(
                  fontSize: 68,
                  fontWeight: FontWeight.w200,
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, MMMM d').format(_now),
                style: TextStyle(fontSize: 15, color: context.mutedColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (zones.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.public, color: context.mutedColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Tap + to add cities and compare their time with yours.',
                    style: TextStyle(color: context.mutedColor),
                  ),
                ),
              ],
            ),
          )
        else
          for (final zoneId in zones)
            _ZoneCard(zoneId: zoneId, now: _now),
      ],
    );
  }
}

class _ZoneCard extends ConsumerWidget {
  const _ZoneCard({required this.zoneId, required this.now});
  final String zoneId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    tz.TZDateTime? there;
    try {
      there = tz.TZDateTime.now(tz.getLocation(zoneId));
    } catch (_) {
      there = null;
    }

    final city = zoneId.split('/').last.replaceAll('_', ' ');
    final region = zoneId.contains('/')
        ? zoneId.substring(0, zoneId.lastIndexOf('/')).replaceAll('_', ' ')
        : '';

    String offsetLabel = '—';
    String dayLabel = '';
    if (there != null) {
      final offsetMinutes =
          there.timeZoneOffset.inMinutes - now.timeZoneOffset.inMinutes;
      if (offsetMinutes == 0) {
        offsetLabel = 'Same time';
      } else {
        final sign = offsetMinutes > 0 ? '+' : '−';
        final abs = offsetMinutes.abs();
        final h = abs ~/ 60;
        final m = abs % 60;
        offsetLabel = m == 0 ? '$sign${h}h' : '$sign${h}h ${m}m';
      }
      final dayDiff = DateTime(there.year, there.month, there.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      dayLabel = switch (dayDiff) {
        1 => 'Tomorrow',
        -1 => 'Yesterday',
        _ => 'Today',
      };
    }

    return Dismissible(
      key: ValueKey(zoneId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      onDismissed: (_) =>
          ref.read(worldClockProvider.notifier).remove(zoneId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    region.isEmpty
                        ? offsetLabel
                        : '$region · $offsetLabel · $dayLabel',
                    style:
                        TextStyle(fontSize: 12.5, color: context.mutedColor),
                  ),
                ],
              ),
            ),
            Text(
              there == null ? '—' : TimeFormat.clock(there),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w300,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
