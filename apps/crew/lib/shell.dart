import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'screens/jobs_home.dart';
import 'screens/pay.dart';
import 'screens/pending.dart';

class CrewShell extends StatefulWidget {
  const CrewShell({super.key});
  @override
  State<CrewShell> createState() => _CrewShellState();
}

class _CrewShellState extends State<CrewShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: IndexedStack(
        index: _index,
        children: const [JobsHomeScreen(), PendingScreen(), PayScreen()],
      ),
      bottomNavigationBar: RBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          RNavItem('Jobs', Icons.work_outline),
          RNavItem('Pending', Icons.schedule, badge: 3),
          RNavItem('Pay', Icons.attach_money),
        ],
      ),
    );
  }
}
