import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'logic.dart';

/// Where a job stands, in the crew's words. A job in progress shows a running
/// clock since it was started.
class CrewStatusPill extends StatelessWidget {
  const CrewStatusPill(this.job, {super.key});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final label = crewStatusLabel(job.status);
    switch (job.status) {
      case JobStatus.open:
        return RPill(label, bg: RColors.amberTint, fg: const Color(0xFF7A5514), dot: RColors.amber);
      case JobStatus.claimed:
        return RPill(label, dot: RColors.teal);
      case JobStatus.inProgress:
        Widget pill(String text) =>
            RPill(text, bg: RColors.lime, fg: RColors.ink, dot: RColors.tealDeep);
        final startedAt = job.startedAt;
        if (startedAt == null) return pill(label);
        return RElapsed(
          since: startedAt,
          builder: (_, elapsed) => pill('$label · ${fmtElapsed(elapsed)}'),
        );
      case JobStatus.done:
        return RPill(label, icon: Icons.check_rounded);
      case JobStatus.cancelled:
        return RPill(label, bg: RColors.dangerTint, fg: RColors.danger);
      case JobStatus.unknown:
        return RPill(label, bg: RColors.paper2, fg: RColors.inkMuted);
    }
  }
}

/// Whether a finished job's pay has reached the crew member yet.
class PaidOutChip extends StatelessWidget {
  const PaidOutChip({super.key, required this.paidOut});
  final bool paidOut;

  @override
  Widget build(BuildContext context) => paidOut
      ? const RChip(
          'Paid out',
          bg: RColors.tealTint,
          fg: RColors.tealDeep,
          icon: Icons.check_rounded,
        )
      : const RChip('Unpaid', bg: RColors.amberTint, fg: Color(0xFF7A5514));
}

/// The first line of a job card: the property on the left, [trailing]
/// (usually what the job pays) on the right.
class JobTitleRow extends StatelessWidget {
  const JobTitleRow(this.title, {super.key, this.trailing, this.size = 14, this.muted = false});
  final String title;
  final Widget? trailing;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: size,
              fontWeight: FontWeight.w700,
              color: muted ? RColors.inkMuted : RColors.ink,
              letterSpacing: size > 14 ? -0.3 : 0,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ],
    );
  }
}

/// One muted line that never wraps (addresses, dates).
class MutedLine extends StatelessWidget {
  const MutedLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: RText.muted);
}
