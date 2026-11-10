import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../crew_data.dart';
import '../job_actions.dart';
import '../logic.dart';
import '../widgets.dart';
import 'job_detail.dart';

/// The Jobs tab: what the crew member is working on, what they accepted and
/// what they finished lately.
class JobsHomeScreen extends StatefulWidget {
  const JobsHomeScreen({super.key, required this.data, required this.active});
  final CrewData data;
  final bool active;

  @override
  State<JobsHomeScreen> createState() => _JobsHomeScreenState();
}

class _JobsHomeScreenState extends State<JobsHomeScreen> {
  static const _recentShown = 6;

  bool _allRecent = false;

  CrewData get _data => widget.data;

  void _open(Job job) => openJobDetail(context, _data, jobId: job.id, initial: job);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: RAppHeader()),
          Expanded(
            child: RLive<List<Job>>(
              controller: _data.mine,
              pollEvery: const Duration(seconds: 15),
              active: widget.active,
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              builder: (context, jobs) => _body(groupMine(jobs)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(MyJobs jobs) {
    final recent = _allRecent ? jobs.recent : jobs.recent.take(_recentShown).toList();
    final hidden = jobs.recent.length - recent.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(longDate(DateTime.now()), style: RText.muted),
        const SizedBox(height: 2),
        // "Earned today" comes from the pay summary, which [CrewData] keeps in
        // step with this list.
        ListenableBuilder(
          listenable: _data.pay,
          builder: (context, _) => Text(
            homeSummary(jobs, _data.pay.data),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: RColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (jobs.toDo == 0) _NothingToDo(data: _data, firstTime: jobs.isEmpty),
        if (jobs.inProgress.isNotEmpty) ...[
          const RSectionLabel('In progress'),
          const SizedBox(height: 8),
          for (final job in jobs.inProgress)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _InProgressCard(job, onTap: () => _open(job)),
            ),
          const SizedBox(height: 8),
        ],
        if (jobs.accepted.isNotEmpty) ...[
          RSectionLabel('Accepted · ${jobs.accepted.length}'),
          const SizedBox(height: 8),
          for (final job in jobs.accepted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AcceptedCard(
                key: ValueKey(job.id),
                job: job,
                data: _data,
                onTap: () => _open(job),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (recent.isNotEmpty) ...[
          const RSectionLabel('Recent'),
          const SizedBox(height: 8),
          for (final job in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecentCard(job, onTap: () => _open(job)),
            ),
          if (hidden > 0)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _allRecent = true),
                style: TextButton.styleFrom(
                  foregroundColor: RColors.tealDeep,
                  textStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: Text('Show $hidden more'),
              ),
            ),
        ],
      ],
    );
  }
}

/// Shown while nothing is accepted or in progress, with a way to the open
/// requests when there are any.
class _NothingToDo extends StatelessWidget {
  const _NothingToDo({required this.data, required this.firstTime});
  final CrewData data;

  /// Whether the crew member has no jobs at all, not even finished ones.
  final bool firstTime;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data.open,
    builder: (context, _) {
      final waiting = data.open.data?.length ?? 0;
      return REmptyState(
        icon: Icons.ac_unit_rounded,
        title: firstTime ? 'No jobs yet' : "You're all caught up",
        message: waiting > 0
            ? 'Accept an open request and it shows up here.'
            : 'When a customer requests a plough it appears in the Open tab.',
        action: waiting > 0
            ? ROutlineButton(
                'See ${countLabel(waiting, 'open request')}',
                color: RColors.tealDeep,
                onPressed: () => data.goTo(CrewTab.open),
              )
            : null,
      );
    },
  );
}

class _InProgressCard extends StatelessWidget {
  const _InProgressCard(this.job, {required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => RCard(
    radius: 14,
    border: Border.all(color: RColors.teal, width: 1.2),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JobTitleRow(job.propertyName, trailing: Text(money(job.crewPay), style: RText.price)),
        const SizedBox(height: 5),
        MutedLine(job.address),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CrewStatusPill(job),
            RServiceTag(shovel: job.shovel),
          ],
        ),
      ],
    ),
  );
}

class _AcceptedCard extends StatefulWidget {
  const _AcceptedCard({super.key, required this.job, required this.data, required this.onTap});
  final Job job;
  final CrewData data;
  final VoidCallback onTap;

  @override
  State<_AcceptedCard> createState() => _AcceptedCardState();
}

class _AcceptedCardState extends State<_AcceptedCard>
    with BusyState<_AcceptedCard>, JobActions<_AcceptedCard> {
  @override
  CrewData get crewData => widget.data;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return RCard(
      radius: 14,
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobTitleRow(job.propertyName, trailing: Text(money(job.crewPay), style: RText.price)),
          const SizedBox(height: 5),
          MutedLine(job.address),
          const SizedBox(height: 12),
          Row(
            children: [
              RServiceTag(shovel: job.shovel),
              const SizedBox(width: 10),
              Expanded(child: MutedLine(jobStatusLine(job))),
            ],
          ),
          const SizedBox(height: 12),
          ROutlineButton(
            'Start',
            icon: Icons.play_arrow_rounded,
            color: RColors.tealDeep,
            fullWidth: true,
            busy: busy,
            // Once the server agrees the job moves to "In progress" in the
            // shared list, and this card goes with it.
            onPressed: () => startJob(job.id),
          ),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard(this.job, {required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = job.status == JobStatus.done;
    final at = finishedAt(job);
    final day = at == null ? '' : fmtDay(at);
    return RCard(
      radius: 14,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobTitleRow(
            job.propertyName,
            muted: !done,
            trailing: done ? Text(money(job.crewPay), style: RText.price) : null,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: MutedLine(
                  done
                      ? [
                          day,
                          serviceLabel(shovel: job.shovel),
                        ].where((s) => s.isNotEmpty).join(' · ')
                      : [cancelledByLabel(job), day].where((s) => s.isNotEmpty).join(' · '),
                ),
              ),
              if (done) ...[const SizedBox(width: 10), PaidOutChip(paidOut: job.paidOut)],
            ],
          ),
        ],
      ),
    );
  }
}
