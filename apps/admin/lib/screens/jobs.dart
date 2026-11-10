import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/job_widgets.dart';
import 'job_detail.dart';
import 'new_job.dart';

/// The server returns at most this many jobs per list.
const _listLimit = 300;

const _ranges = [7, 30, 90];

/// The jobs of a history list that pass [filter].
List<Job> filterHistory(List<Job> jobs, HistoryFilter filter) => switch (filter) {
  HistoryFilter.all => jobs,
  HistoryFilter.done => jobs.where((j) => j.status == JobStatus.done).toList(),
  HistoryFilter.cancelled => jobs.where((j) => j.status == JobStatus.cancelled).toList(),
  HistoryFilter.needsPayment => jobs.where(needsPayment).toList(),
};

/// The Jobs tab: what is live, what was requested today, and the history.
/// The shell owns [view] and [filter] so other tabs can link into them.
class JobsScreen extends StatefulWidget {
  const JobsScreen({
    super.key,
    required this.active,
    required this.view,
    required this.filter,
    required this.onViewChanged,
    required this.onFilterChanged,
  });

  /// Whether this tab is the one in front.
  final bool active;
  final JobsView view;
  final HistoryFilter filter;
  final ValueChanged<JobsView> onViewChanged;
  final ValueChanged<HistoryFilter> onFilterChanged;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  int _rangeDays = _ranges.first;

  late final RLiveController<List<Job>> _live = RLiveController(
    () => api.jobs(status: const [JobStatus.open, JobStatus.claimed, JobStatus.inProgress]),
  );
  late final RLiveController<List<Job>> _today = RLiveController(() {
    final now = DateTime.now();
    return api.jobs(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime(now.year, now.month, now.day + 1),
    );
  });
  late final RLiveController<List<Job>> _history = RLiveController(
    () => api.jobs(from: DateTime.now().subtract(Duration(days: _rangeDays))),
  );
  // Unpaid jobs are listed whatever their age: an old debt must not drop out
  // of sight with the date range.
  late final RLiveController<List<Job>> _unpaid = RLiveController(
    () => api.jobs(payment: const [PaymentStatus.due, PaymentStatus.failed]),
  );

  @override
  void dispose() {
    _live.dispose();
    _today.dispose();
    _history.dispose();
    _unpaid.dispose();
    super.dispose();
  }

  void _setRange(int days) {
    if (days == _rangeDays) return;
    setState(() => _rangeDays = days);
    _history.refresh();
  }

  void _open(Job job) =>
      pushScreen<void>(context, AdminJobDetailScreen(jobId: job.id, initial: job));

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final filter = widget.filter;
    final unpaidOnly = filter == HistoryFilter.needsPayment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Jobs', style: RText.h1)),
                  ROutlineButton(
                    'New job',
                    icon: Icons.add_rounded,
                    color: RColors.tealDeep,
                    onPressed: () => startNewJob(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RSegmented(
                options: const ['Active', 'Today', 'History'],
                index: view.index,
                onChanged: (i) => widget.onViewChanged(JobsView.values[i]),
              ),
              if (view == JobsView.history) ...[
                const SizedBox(height: 12),
                FilterRow(
                  children: [
                    for (final (value, label) in const [
                      (HistoryFilter.all, 'All'),
                      (HistoryFilter.done, 'Done'),
                      (HistoryFilter.cancelled, 'Cancelled'),
                      (HistoryFilter.needsPayment, 'Needs payment'),
                    ])
                      FilterPill(
                        label: label,
                        selected: filter == value,
                        onTap: () => widget.onFilterChanged(value),
                      ),
                  ],
                ),
                if (!unpaidOnly) ...[
                  const SizedBox(height: 8),
                  FilterRow(
                    children: [
                      for (final days in _ranges)
                        FilterPill(
                          label: 'Last $days days',
                          selected: days == _rangeDays,
                          onTap: () => _setRange(days),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        Expanded(
          child: switch (view) {
            JobsView.active => RLive<List<Job>>(
              key: const ValueKey(JobsView.active),
              controller: _live,
              active: widget.active,
              pollEvery: const Duration(seconds: 10),
              padding: tabPadding,
              builder: (_, jobs) => _ActiveList(jobs: jobs, onOpen: _open),
            ),
            JobsView.today => RLive<List<Job>>(
              key: const ValueKey(JobsView.today),
              controller: _today,
              active: widget.active,
              pollEvery: const Duration(seconds: 20),
              padding: tabPadding,
              builder: (_, jobs) => _TodayList(jobs: jobs, onOpen: _open),
            ),
            // No timer: the list reloads on entering the view, on coming back
            // from a job, and on pull to refresh.
            JobsView.history => RLive<List<Job>>(
              key: ValueKey(unpaidOnly),
              controller: unpaidOnly ? _unpaid : _history,
              active: widget.active,
              padding: tabPadding,
              builder: (_, jobs) => _HistoryList(
                jobs: filterHistory(jobs, filter),
                loaded: jobs.length,
                filter: filter,
                rangeDays: _rangeDays,
                onOpen: _open,
              ),
            ),
          },
        ),
      ],
    );
  }
}

class _ActiveList extends StatelessWidget {
  const _ActiveList({required this.jobs, required this.onOpen});
  final List<Job> jobs;
  final ValueChanged<Job> onOpen;

  @override
  Widget build(BuildContext context) {
    final groups = groupLive(jobs);
    final sections = [
      ('Waiting for crew', groups.waiting),
      ('Crew assigned', groups.assigned),
      ('In progress', groups.inProgress),
    ];
    if (sections.every((s) => s.$2.isEmpty)) {
      return const REmptyState(
        icon: Icons.ac_unit_rounded,
        title: 'No active jobs',
        message: 'A request shows up here the moment a customer asks for a plough.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, group) in sections)
          if (group.isNotEmpty) ...[
            RSectionLabel('$title · ${group.length}'),
            const SizedBox(height: 8),
            ListCard(children: [for (final job in group) JobRow(job, onTap: () => onOpen(job))]),
            const SizedBox(height: 18),
          ],
      ],
    );
  }
}

class _TodayList extends StatelessWidget {
  const _TodayList({required this.jobs, required this.onOpen});
  final List<Job> jobs;
  final ValueChanged<Job> onOpen;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const REmptyState(
        icon: Icons.wb_sunny_outlined,
        title: 'No requests today',
        message: 'Ploughs requested since midnight are listed here.',
      );
    }
    final totals = summarizeJobs(jobs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${totals.requested} requested · ${totals.done} done · '
          '${totals.cancelled} cancelled · ${money(totals.billed)} billed',
          style: RText.muted,
        ),
        const SizedBox(height: 10),
        ListCard(children: [for (final job in jobs) JobRow(job, onTap: () => onOpen(job))]),
      ],
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.jobs,
    required this.loaded,
    required this.filter,
    required this.rangeDays,
    required this.onOpen,
  });

  /// The jobs that pass [filter].
  final List<Job> jobs;

  /// How many jobs the server returned before filtering.
  final int loaded;
  final HistoryFilter filter;
  final int rangeDays;
  final ValueChanged<Job> onOpen;

  @override
  Widget build(BuildContext context) {
    final unpaidOnly = filter == HistoryFilter.needsPayment;
    if (jobs.isEmpty) {
      return REmptyState(
        icon: unpaidOnly ? Icons.verified_outlined : Icons.history_rounded,
        title: switch (filter) {
          HistoryFilter.all => 'No jobs in the last $rangeDays days',
          HistoryFilter.done => 'No finished jobs in the last $rangeDays days',
          HistoryFilter.cancelled => 'No cancelled jobs in the last $rangeDays days',
          HistoryFilter.needsPayment => 'Nothing to collect',
        },
        message: unpaidOnly
            ? 'Every finished job has been paid.'
            : 'Try a longer range or another filter.',
      );
    }
    final owed = jobs.fold<int>(0, (sum, job) => sum + job.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          unpaidOnly
              ? '${countOf(jobs.length, 'job')} · ${money(owed)} to collect · any date'
              : '${countOf(jobs.length, 'job')} requested in the last $rangeDays days',
          style: RText.muted,
        ),
        const SizedBox(height: 10),
        ListCard(children: [for (final job in jobs) JobRow(job, onTap: () => onOpen(job))]),
        if (loaded >= _listLimit) ...[
          const SizedBox(height: 10),
          Text(
            unpaidOnly
                ? 'Showing the newest $_listLimit unpaid jobs.'
                : 'Showing the newest $_listLimit jobs. Pick a shorter range to see fewer.',
            style: RText.muted,
          ),
        ],
      ],
    );
  }
}
