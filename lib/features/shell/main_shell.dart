import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_protocol/sync_protocol.dart';

import '../../services/system_sounds.dart';
import '../alarm/presentation/alarm_edit_screen.dart';
import '../alarm/presentation/alarm_list_screen.dart';
import '../clock/clock_screen.dart';
import '../clock/world_clock_add_screen.dart';
import '../schedules/shift_schedules_screen.dart';
import '../settings/settings_screen.dart';
import '../stopwatch/stopwatch_screen.dart';
import '../sync/sync_screen.dart';
import '../timer/timer_screen.dart';

/// The app shell: the four standard clock-app tabs. Features live on the tab
/// they belong to — shift schedules on the Alarm tab's app bar, the settings
/// gear on every tab. No drawer.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const _titles = ['Alarms', 'Clock', 'Stopwatch', 'Timer'];

  final _pages = const [
    AlarmListScreen(),
    ClockScreen(),
    StopwatchScreen(),
    TimerScreen(),
  ];

  @override
  void initState() {
    super.initState();
    final bridge = ref.read(systemSoundsProvider);
    // Widget tap while the app is running.
    bridge.onOpenTab = (tab) {
      if (mounted && tab >= 0 && tab < _pages.length) {
        setState(() => _index = tab);
      }
    };
    // Widget tap that cold-launched the app.
    bridge.initialTab().then((tab) {
      if (mounted && tab >= 0 && tab < _pages.length) {
        setState(() => _index = tab);
      }
    });
    // Session QR / link, either way the app was reached.
    bridge.onSyncLink = _openSyncLink;
    bridge.initialSyncLink().then((link) {
      if (link != null) _openSyncLink(link);
    });
  }

  void _openSyncLink(String raw) {
    final link = SyncLink.parse(raw);
    if (link == null || !mounted) return;
    setState(() => _index = 3); // Timer tab, where the banner lives
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SyncScreen(initialLink: link)),
    );
  }

  @override
  void dispose() {
    final bridge = ref.read(systemSoundsProvider);
    bridge.onOpenTab = null;
    bridge.onSyncLink = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (_index == 0)
            IconButton(
              tooltip: 'Shift schedules',
              icon: const Icon(Icons.repeat),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ShiftSchedulesScreen(),
                ),
              ),
            ),
          if (_index == 2 || _index == 3)
            IconButton(
              tooltip: 'Time Sync',
              icon: const Icon(Icons.link),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              ),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: switch (_index) {
        0 => FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AlarmEditScreen()),
          ),
          child: const Icon(Icons.add),
        ),
        1 => FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WorldClockAddScreen()),
          ),
          child: const Icon(Icons.add),
        ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.alarm_outlined),
            selectedIcon: Icon(Icons.alarm),
            label: 'Alarm',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Clock',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Stopwatch',
          ),
          NavigationDestination(
            icon: Icon(Icons.hourglass_empty),
            selectedIcon: Icon(Icons.hourglass_bottom),
            label: 'Timer',
          ),
        ],
      ),
    );
  }
}
