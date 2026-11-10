import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../logic.dart';
import '../widgets.dart';

/// Everything about one plough request: where it stands, who did it, what it
/// cost and how it was paid. Read-only; kept fresh while the job is under way.
class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({super.key, required this.jobId, this.initial});
  final String jobId;

  /// The job as the previous screen had it, shown until the fresh copy lands.
  final Job? initial;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late final _job = RLiveController<Job>(() => api.job(widget.jobId));

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _job.setData(initial);
  }

  @override
  void dispose() {
    _job.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PushedScreen(
    child: ListenableBuilder(
      listenable: _job,
      builder: (context, _) => RLive<Job>(
        controller: _job,
        pollEvery: (_job.data?.isActive ?? false) ? const Duration(seconds: 10) : null,
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
        builder: (_, job) => _JobDetail(job),
      ),
    ),
  );
}

class _JobDetail extends StatelessWidget {
  const _JobDetail(this.job);
  final Job job;

  @override
  Widget build(BuildContext context) {
    final started = job.startedAt;
    final duration = job.duration;
    final summary = paymentSummary(job);
    final failed = job.payment.status == PaymentStatus.failed;
    final paymentError = job.payment.error ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(job.propertyName, style: RText.h1),
        const SizedBox(height: 4),
        Text(
          job.address,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            RServiceTag(shovel: job.shovel),
            RJobStatusPill(job.status),
          ],
        ),
        const SizedBox(height: 18),
        RCard(
          radius: 14,
          padding: const EdgeInsets.all(18),
          child: job.status == JobStatus.inProgress && started != null
              ? RElapsed(
                  since: started,
                  builder: (_, elapsed) => RStepTracker(steps: jobSteps(job, elapsed: elapsed)),
                )
              : RStepTracker(steps: jobSteps(job)),
        ),
        if (job.crewName.isNotEmpty || duration != null) ...[
          const SizedBox(height: 12),
          RCard(
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                if (job.crewName.isNotEmpty)
                  DetailRow(
                    'Crew',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RAvatar(job.crewInitials, colorKey: job.crewColor, size: 22),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            job.crewName,
                            style: RText.body,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (job.crewName.isNotEmpty && duration != null) const RowDivider(),
                if (duration != null) DetailRow('Time on site', value: fmtDuration(duration)),
              ],
            ),
          ),
        ],
        if (job.note.isNotEmpty) ...[
          const SizedBox(height: 18),
          const RSectionLabel('Your note'),
          const SizedBox(height: 8),
          Text(job.note, style: RText.body.copyWith(height: 1.55)),
        ],
        if (job.crewNote.isNotEmpty) ...[
          const SizedBox(height: 18),
          const RSectionLabel('Crew note'),
          const SizedBox(height: 8),
          Text(
            job.crewNote,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: const Color(0xFF555555),
              height: 1.55,
            ),
          ),
        ],
        const SizedBox(height: 18),
        RSectionLabel(job.status == JobStatus.cancelled ? 'Price · not charged' : 'Price'),
        const SizedBox(height: 8),
        RCard(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              DetailRow('Plough', value: money(job.price)),
              if (job.shovel) ...[
                const RowDivider(),
                DetailRow('Shovelling', value: money(job.shovelPrice)),
              ],
              const RowDivider(),
              DetailRow('Total', value: money(job.total), strong: true),
            ],
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 18),
          RSectionLabel('Payment', trailing: JobPaymentPill(job)),
          const SizedBox(height: 8),
          Text(summary, style: RText.body.copyWith(height: 1.5)),
          // The server's own explanation: why a charge failed, or that a
          // hold could not be released yet.
          if (paymentError.isNotEmpty) ...[
            const SizedBox(height: 8),
            RBanner(paymentError, error: failed),
          ],
        ],
      ],
    );
  }
}
