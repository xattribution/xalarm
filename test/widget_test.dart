import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xalarm/core/theme/app_theme.dart';
import 'package:xalarm/features/schedules/shift_schedules_screen.dart';

void main() {
  testWidgets('Shift schedules screen lists the Panama preset', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ShiftSchedulesScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Shift schedules'), findsOneWidget);
    expect(find.text('Panama (2-2-3)'), findsOneWidget);
    expect(find.text('4-on / 4-off'), findsOneWidget);
    expect(find.text('New schedule'), findsOneWidget);
  });
}
