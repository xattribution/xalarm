import 'package:flutter/material.dart';

import '../../core/widgets/coming_soon.dart';

class StopwatchScreen extends StatelessWidget {
  const StopwatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.timer_outlined,
      title: 'Stopwatch',
      subtitle: 'Start, lap, and reset — arriving in the next milestone.',
    );
  }
}
