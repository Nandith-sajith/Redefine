import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'screens/crew.dart';
import 'screens/customers.dart';
import 'screens/home.dart';
import 'screens/schedule.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: IndexedStack(
        index: _index,
        children: const [HomeScreen(), ScheduleScreen(), CustomersScreen(), CrewScreen()],
      ),
      bottomNavigationBar: RBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          RNavItem('Home', Icons.grid_view_rounded),
          RNavItem('Schedule', Icons.calendar_today_outlined),
          RNavItem('Customers', Icons.people_outline),
          RNavItem('Crew', Icons.person_outline),
        ],
      ),
    );
  }
}
