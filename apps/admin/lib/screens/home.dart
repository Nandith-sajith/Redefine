import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/job_widgets.dart';
import 'job_detail.dart';
import 'new_job.dart';
import 'quote_detail.dart';

/// The Home tab: today's numbers, what is waiting on the office and every
/// job that is live right now.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.dash, required this.goTo});

  /// Owned by the shell, which also draws its badges from it.
  final RLiveController<AdminDashboard> dash;
  final GoTo goTo;

  @override
  Widget build(BuildContext context) => RLive<AdminDashboard>(
    controller: dash,
    // Not tied to this tab being in front: the badges on the bottom bar must
    // stay current on every tab.
    pollEvery: const Duration(seconds: 10),
    padding: tabPadding,
    builder: (context, dashboard) => _HomeBody(dashboard: dashboard, goTo: goTo),
  );
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.dashboard, required this.goTo});
  final AdminDashboard dashboard;
  final GoTo goTo;

  @override
  Widget build(BuildContext context) {
    final counts = dashboard.counts;
    final quotes = dashboard.pendingQuotes;
    final applicants = dashboard.pendingCrew;
    final live = dashboard.liveJobs;
    final owed = dashboard.paymentIssues.fold<int>(0, (sum, job) => sum + job.total);
    final needsAttention = quotes.isNotEmpty || applicants.isNotEmpty || counts.paymentIssues > 0;

    void openJobs(JobsView view) => goTo(AdminTab.jobs, view: view);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fmtLongDate(dashboard.serverTime ?? DateTime.now()), style: RText.h1),
        const SizedBox(height: 4),
        Text(
          '${countOf(counts.doneToday, 'plough')} done today · ${money(counts.revenueToday)} billed',
          style: RText.muted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Waiting for crew',
                value: '${counts.openJobs}',
                valueColor: counts.openJobs > 0 ? amberInk : RColors.ink,
                onTap: () => openJobs(JobsView.active),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Crew assigned',
                value: '${counts.claimedJobs}',
                onTap: () => openJobs(JobsView.active),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'In progress',
                value: '${counts.inProgressJobs}',
                onTap: () => openJobs(JobsView.active),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Done today',
                value: '${counts.doneToday}',
                valueColor: RColors.tealDeep,
                onTap: () => openJobs(JobsView.today),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ROutlineButton(
          'New job',
          icon: Icons.add_rounded,
          color: RColors.tealDeep,
          fullWidth: true,
          onPressed: () => startNewJob(context),
        ),
        if (needsAttention) ...[
          const SizedBox(height: 22),
          const RSectionLabel('Needs attention'),
          const SizedBox(height: 8),
          for (final quote in quotes)
            _AttentionCard(
              icon: Icons.request_quote_outlined,
              title: 'Quote request · ${quote.customerName}',
              subtitle: [
                quote.propertyName,
                quote.address,
                if (quote.createdAt != null) 'requested ${fmtAgo(quote.createdAt!)}',
              ].join(' · '),
              onTap: () => pushScreen<bool>(context, QuoteDetailScreen(quoteId: quote.id)),
            ),
          for (final member in applicants)
            _AttentionCard(
              icon: Icons.person_add_alt_1_outlined,
              title: '${member.name} applied to join the crew',
              subtitle: member.appliedAt == null
                  ? 'Waiting for your approval'
                  : 'Applied ${fmtAgo(member.appliedAt!)} · waiting for your approval',
              onTap: () => goTo(AdminTab.crew),
            ),
          if (counts.paymentIssues > 0)
            _AttentionCard(
              icon: Icons.credit_card_off_outlined,
              title: 'Payment issues · ${counts.paymentIssues}',
              subtitle: owed > 0
                  ? '${money(owed)} still to collect'
                  : 'Charges that failed or are still due',
              onTap: () =>
                  goTo(AdminTab.jobs, view: JobsView.history, filter: HistoryFilter.needsPayment),
            ),
        ],
        const SizedBox(height: 14),
        RSectionLabel('Live now${live.isEmpty ? '' : ' · ${live.length}'}'),
        const SizedBox(height: 8),
        if (live.isEmpty)
          const RCard(
            padding: EdgeInsets.zero,
            child: REmptyState(
              icon: Icons.ac_unit_rounded,
              title: 'All clear',
              message: 'No plough is waiting or under way. New requests appear here on their own.',
            ),
          )
        else
          ListCard(
            children: [
              for (final job in live)
                JobRow(
                  job,
                  onTap: () =>
                      pushScreen<void>(context, AdminJobDetailScreen(jobId: job.id, initial: job)),
                ),
            ],
          ),
      ],
    );
  }
}

/// One thing waiting on the office: icon, what it is, a line of detail.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: RCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: RColors.paper2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: RColors.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RText.title.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: RText.muted.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          rowChevron,
        ],
      ),
    ),
  );
}
