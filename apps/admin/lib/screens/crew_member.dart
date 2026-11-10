import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';
import '../widgets/job_widgets.dart';
import 'job_detail.dart';

/// One crew member: contact details, what they earned, the finished jobs
/// they have not been paid for yet, and the payouts recorded so far.
class CrewMemberScreen extends StatefulWidget {
  const CrewMemberScreen({super.key, required this.member});
  final CrewMember member;

  @override
  State<CrewMemberScreen> createState() => _CrewMemberScreenState();
}

class _CrewMemberScreenState extends State<CrewMemberScreen> with BusyState<CrewMemberScreen> {
  late final RLiveController<CrewPay> _pay = RLiveController(() => api.crewPay(widget.member.id));

  @override
  void dispose() {
    _pay.dispose();
    super.dispose();
  }

  Future<void> _recordPayout(CrewPay pay) async {
    final member = widget.member;
    final confirmed = await confirmDialog(
      context,
      title: 'Record payout?',
      message:
          'Record ${money(pay.unpaidTotal)} paid to ${member.name} for '
          '${countOf(pay.unpaidJobs.length, 'job')}? This only keeps the books: pay them '
          'yourself first.',
      confirmLabel: 'Record payout',
    );
    if (!confirmed || !mounted) return;
    final result = await run(
      () => api.recordPayout(member.id),
      onError: (e) {
        // Already paid out, from another device perhaps: show the books as they are.
        if (e.code == 'nothing_to_pay') _pay.refresh(silent: true);
        return false;
      },
    );
    if (result == null || !mounted) return;
    _pay.setData(result.pay);
    showRSnack(context, 'Recorded ${money(result.payout.amount)} paid to ${member.name}');
  }

  @override
  Widget build(BuildContext context) => PushedPage(
    child: RLive<CrewPay>(
      controller: _pay,
      pollEvery: const Duration(seconds: 30),
      padding: pagePadding,
      builder: (context, pay) => _body(pay),
    ),
  );

  Widget _body(CrewPay pay) {
    final member = widget.member;
    final applied = member.appliedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RAvatar(
              member.initials,
              colorKey: member.color.isEmpty ? 'lime' : member.color,
              size: 56,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: RColors.ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusPill(member.status),
                      if (applied != null) Text('Applied ${fmtDay(applied)}', style: RText.muted),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (member.email.isNotEmpty || member.phone.isNotEmpty) ...[
          const SizedBox(height: 16),
          ContactCard(email: member.email, phone: member.phone),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatTile(label: 'Today', value: money(pay.earnedToday)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(label: 'This week', value: money(pay.earnedThisWeek)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(label: 'All time', value: money(pay.earnedAllTime)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${countOf(pay.jobsToday, 'job')} today · ${countOf(pay.jobsThisWeek, 'job')} this week',
          style: RText.muted,
        ),
        const SizedBox(height: 16),
        RCard(
          color: RColors.tealTint,
          border: Border.all(color: RColors.tealTint),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UNPAID BALANCE', style: RText.eyebrow.copyWith(color: RColors.tealDeep)),
              const SizedBox(height: 6),
              Text(
                money(pay.unpaidTotal),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: RColors.tealDeep,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                pay.unpaidJobs.isEmpty
                    ? 'Every finished job has been paid out.'
                    : 'For ${countOf(pay.unpaidJobs.length, 'finished job')}',
                style: RText.muted.copyWith(color: RColors.tealDeep),
              ),
              const SizedBox(height: 14),
              RPrimaryButton(
                'Record payout',
                icon: Icons.payments_outlined,
                busy: busy,
                onPressed: pay.unpaidTotal > 0 ? () => _recordPayout(pay) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        RSectionLabel('Unpaid jobs${pay.unpaidJobs.isEmpty ? '' : ' · ${pay.unpaidJobs.length}'}'),
        const SizedBox(height: 8),
        if (pay.unpaidJobs.isEmpty)
          const TextCard('Nothing unpaid.')
        else
          ListCard(radius: 14, children: [for (final job in pay.unpaidJobs) _unpaidRow(job)]),
        const SizedBox(height: 18),
        const RSectionLabel('Payout history'),
        const SizedBox(height: 8),
        if (pay.payouts.isEmpty)
          const TextCard('No payouts yet.')
        else
          ListCard(radius: 14, children: [for (final payout in pay.payouts) _PayoutRow(payout)]),
      ],
    );
  }

  // These jobs come in the crew's view, without the customer's price, so the
  // row says what the crew member earned and the detail page loads its own.
  Widget _unpaidRow(Job job) {
    final completed = job.completedAt;
    return JobRow(
      job,
      meta: [
        completed == null ? 'Done' : 'Done ${fmtDayTime(completed)}',
        if (job.shovel) 'with shovelling',
      ].join(' · '),
      trailing: Text(money(job.crewPay), style: RText.price.copyWith(fontSize: 14)),
      onTap: () => pushScreen<void>(context, AdminJobDetailScreen(jobId: job.id)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final CrewStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    CrewStatus.active => const RPill('ACTIVE', dot: RColors.teal),
    CrewStatus.pending => const RPill(
      'PENDING APPROVAL',
      bg: RColors.amberTint,
      fg: amberInk,
      dot: RColors.amber,
    ),
    CrewStatus.rejected => const RPill('REJECTED', bg: RColors.dangerTint, fg: RColors.danger),
    CrewStatus.unknown => const RPill('UNKNOWN', bg: RColors.paper2, fg: RColors.inkMuted),
  };
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow(this.payout);
  final Payout payout;

  @override
  Widget build(BuildContext context) {
    final paid = payout.paidAt;
    return ListRow(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paid == null ? 'Payout' : fmtDay(paid),
                  style: RText.title.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    countOf(payout.jobCount, 'job'),
                    if (payout.note.isNotEmpty) payout.note,
                  ].join(' · '),
                  style: RText.muted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(money(payout.amount), style: RText.price.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}
