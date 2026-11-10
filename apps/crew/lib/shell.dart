import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'crew_data.dart';
import 'screens/jobs_home.dart';
import 'screens/open_jobs.dart';
import 'screens/pay.dart';

/// The approved crew member's app: Jobs | Open | Pay.
class CrewShell extends StatefulWidget {
  const CrewShell({super.key});

  @override
  State<CrewShell> createState() => _CrewShellState();
}

class _CrewShellState extends State<CrewShell> {
  late final CrewData _data = CrewData(goTo: _goTo);
  int _index = CrewTab.jobs;

  void _goTo(int tab) {
    if (mounted && tab != _index) setState(() => _index = tab);
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: IndexedStack(
        index: _index,
        children: [
          JobsHomeScreen(data: _data, active: _index == CrewTab.jobs),
          // Stays live on every tab: its list feeds the badge below.
          OpenJobsScreen(data: _data, active: _index == CrewTab.open),
          PayScreen(data: _data, active: _index == CrewTab.pay),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _data.open,
        builder: (context, _) => RBottomNav(
          currentIndex: _index,
          onTap: _goTo,
          items: [
            const RNavItem('Jobs', Icons.work_outline),
            RNavItem('Open', Icons.ac_unit_rounded, badge: _data.open.data?.length),
            const RNavItem('Pay', Icons.attach_money),
          ],
        ),
      ),
    );
  }
}
