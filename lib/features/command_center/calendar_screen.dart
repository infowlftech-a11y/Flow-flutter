import 'package:flutter/material.dart';

import 'schedule_tab.dart';

/// The trainer's calendar as a destination.
///
/// A thin wrapper: [ScheduleTab] already owns the day navigator, the walk-in
/// and time-off actions and the hour timeline, and it was written to sit
/// inside a tab view. Lifting it to the navigation bar is a change of where
/// it is reached from, not what it does — so this adds a Scaffold and nothing
/// else, rather than forking a second copy of a 770-line screen.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: ScheduleTab()),
    );
  }
}
