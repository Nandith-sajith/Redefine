import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../crew_data.dart';
import '../logic.dart';
import '../widgets.dart';
import 'job_detail.dart';

/// The Pay tab: what the office still owes, what was earned, and the payouts
/// received so far.
class PayScreen extends StatelessWidget {
  const PayScreen({super.key, required this.data, required this.active});
  final CrewData data;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: RAppHeader()),
          Expanded(
            child: RLive<CrewPay>(
              controller: data.pay,
              pollEvery: const Duration(seconds: 60),
              active: active,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              builder: (context, pay) => _body(context, pay),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, CrewPay pay) {
    final unpaid = pay.unpaidJobs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RCard(
          radius: 18,
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('UNPAID BALANCE', style: RText.eyebrow),
                const SizedBox(height: 10),
                Text(
                  money(pay.unpaidTotal),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: RColors.teal,
                    letterSpacing: -1.5,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  unpaid.isNotEmpty
                      ? '${countLabel(unpaid.length, 'job')} waiting for the next payout'
                      : pay.earnedAllTime > 0
                      ? 'Everything you earned has been paid out'
                      : 'Your first completed job starts the balance',
                  style: RText.muted,
                ),
                const SizedBox(height: 8),
                Text(
                  'The office pays your whole unpaid balance in one payout.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkSoft),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const RSectionLabel('Earned'),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard('Today', pay.earnedToday, note: countLabel(pay.jobsToday, 'job')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  'This week',
                  pay.earnedThisWeek,
                  note: countLabel(pay.jobsThisWeek, 'job'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _StatCard('All time', pay.earnedAllTime)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        RSectionLabel(unpaid.isEmpty ? 'Unpaid jobs' : 'Unpaid jobs · ${unpaid.length}'),
        const SizedBox(height: 8),
        if (unpaid.isEmpty)
          const REmptyState(
            icon: Icons.payments_outlined,
            title: 'Nothing unpaid',
            message: 'Completed jobs are listed here until the office pays them out.',
          ),
        for (final job in unpaid)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _UnpaidJobCard(
              job,
              onTap: () => openJobDetail(context, data, jobId: job.id, initial: job),
            ),
          ),
        const SizedBox(height: 10),
        const RSectionLabel('Payout history'),
        const SizedBox(height: 8),
        if (pay.payouts.isEmpty)
          const REmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No payouts yet',
            message: 'Every payout the office records for you shows up here.',
          )
        else
          RCard(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < pay.payouts.length; i++)
                  _PayoutRow(pay.payouts[i], divider: i > 0),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.amount, {this.note});
  final String label;
  final int amount;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return RCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: RText.eyebrow, maxLines: 1),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(amount),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: RColors.teal,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (note != null) ...[const SizedBox(height: 4), MutedLine(note)],
        ],
      ),
    );
  }
}

class _UnpaidJobCard extends StatelessWidget {
  const _UnpaidJobCard(this.job, {required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completedAt = job.completedAt;
    return RCard(
      radius: 14,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobTitleRow(job.propertyName, trailing: Text(money(job.crewPay), style: RText.price)),
          const SizedBox(height: 5),
          MutedLine(
            [
              if (completedAt != null) fmtDay(completedAt),
              serviceLabel(shovel: job.shovel),
            ].join(' · '),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow(this.payout, {required this.divider});
  final Payout payout;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final paidAt = payout.paidAt;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: divider
            ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paidAt == null ? 'Payout' : fmtDay(paidAt),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: RColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 5.5,
                      backgroundColor: RColors.teal,
                      child: Icon(Icons.check, size: 7, color: RColors.white),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        [
                          countLabel(payout.jobCount, 'job'),
                          if (payout.note.isNotEmpty) payout.note,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: RColors.tealDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            money(payout.amount),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: RColors.ink,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
