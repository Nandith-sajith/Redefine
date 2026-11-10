import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'nav.dart';
import 'screens/crew.dart';
import 'screens/customers.dart';
import 'screens/home.dart';
import 'screens/jobs.dart';
import 'screens/settings.dart';
import 'widgets/common.dart';

/// The signed-in app: account header, four tabs and the bottom bar.
///
/// Owns the dashboard, which feeds the Home tab and the bar's badges.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late final RLiveController<AdminDashboard> _dash = RLiveController(() => api.adminDashboard());
  AdminTab _tab = AdminTab.home;
  JobsView _jobsView = JobsView.active;
  HistoryFilter _historyFilter = HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _dash.addListener(_onDashboard);
  }

  @override
  void dispose() {
    _dash.dispose();
    super.dispose();
  }

  // The badges are drawn from the dashboard.
  void _onDashboard() {
    if (mounted) setState(() {});
  }

  void _goTo(AdminTab tab, {JobsView? view, HistoryFilter? filter}) {
    // Coming back to Home should not wait for the next poll.
    if (tab == AdminTab.home && _tab != AdminTab.home) _dash.refresh(silent: true);
    setState(() {
      _tab = tab;
      _jobsView = view ?? _jobsView;
      _historyFilter = filter ?? _historyFilter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final counts = _dash.data?.counts;
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: RAppHeader(
                actions: [
                  RMenuAction(
                    'Settings',
                    Icons.settings_outlined,
                    () => pushScreen<void>(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                sizing: StackFit.expand,
                children: [
                  HomeScreen(dash: _dash, goTo: _goTo),
                  JobsScreen(
                    active: _tab == AdminTab.jobs,
                    view: _jobsView,
                    filter: _historyFilter,
                    onViewChanged: (view) => setState(() => _jobsView = view),
                    onFilterChanged: (filter) => setState(() => _historyFilter = filter),
                  ),
                  CustomersScreen(active: _tab == AdminTab.customers),
                  CrewScreen(
                    active: _tab == AdminTab.crew,
                    onChanged: () => _dash.refresh(silent: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: RBottomNav(
        currentIndex: _tab.index,
        onTap: (i) => _goTo(AdminTab.values[i]),
        items: [
          RNavItem(
            'Home',
            Icons.grid_view_rounded,
            badge: counts == null ? null : counts.pendingQuotes + counts.paymentIssues,
          ),
          RNavItem('Jobs', Icons.ac_unit_rounded, badge: counts?.openJobs),
          RNavItem('Customers', Icons.people_outline),
          RNavItem('Crew', Icons.person_outline, badge: counts?.pendingCrew),
        ],
      ),
    );
  }
}
