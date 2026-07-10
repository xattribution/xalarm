import 'package:flutter/material.dart';

import '../../core/widgets/coming_soon.dart';

class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.hourglass_empty,
      title: 'Timer',
      subtitle: 'Countdown timers with presets — arriving in the next milestone.',
    );
  }
}
