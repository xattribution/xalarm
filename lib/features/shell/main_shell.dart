import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../alarm/presentation/alarm_edit_screen.dart';
import '../alarm/presentation/alarm_list_screen.dart';
import '../clock/clock_screen.dart';
import '../clock/world_clock_add_screen.dart';
import '../schedules/shift_schedules_screen.dart';
import '../settings/settings_screen.dart';
import '../stopwatch/stopwatch_screen.dart';
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
