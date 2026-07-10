import 'dart:async';

import 'package:alarm/alarm.dart' as pkg;
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/alarm/application/alarm_providers.dart';
import 'features/alarm/presentation/ring_screen.dart';
import 'features/shell/main_shell.dart';
import 'services/permissions_service.dart';

/// Global navigator so the alarm ring stream (which fires outside the widget
/// tree) can push the full-screen ring UI.
final navigatorKey = GlobalKey<NavigatorState>();

/// App theme mode. Defaults to dark — the black/blue/tan hero look.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;
}

class XalarmApp extends ConsumerStatefulWidget {
  const XalarmApp({super.key});

  @override
  ConsumerState<XalarmApp> createState() => _XalarmAppState();
}

class _XalarmAppState extends ConsumerState<XalarmApp> {
  StreamSubscription<AlarmSet>? _ringSub;
  final _shownRinging = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final scheduler = ref.read(alarmSchedulerProvider);
    try {
      await scheduler.init();
    } catch (e) {
      debugPrint('Alarm scheduler init failed (non-mobile platform?): $e');
      return;
    }

    await const PermissionsService().requestAll();
    // Ensure the OS reflects the persisted alarm list.
    await ref.read(alarmListProvider.notifier).resyncAllWithOs();

    _ringSub = pkg.Alarm.ringing.listen(_onRinging);
  }

  void _onRinging(AlarmSet set) {
    for (final ringing in set.alarms) {
      if (_shownRinging.contains(ringing.id)) continue;
      _shownRinging.add(ringing.id);
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => RingScreen(
            nativeId: ringing.id,
            onClosed: () => _shownRinging.remove(ringing.id),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'xalarm',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: mode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const MainShell(),
    );
  }
}
