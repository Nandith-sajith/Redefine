// How a plough job is shown across the admin app, and the pure helpers
// behind the job lists.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'common.dart';

/// An open request nobody has accepted for this long is flagged in amber.
const waitingTooLongAfter = Duration(minutes: 15);

/// Dark amber that stays readable as text.
const amberInk = Color(0xFF7A5514);

/// Whether the customer still owes for [job]: its charge failed, or it was
/// billed manually and has not been marked paid.
bool needsPayment(Job job) =>
    job.payment.status == PaymentStatus.due || job.payment.status == PaymentStatus.failed;

typedef LiveGroups = ({List<Job> waiting, List<Job> assigned, List<Job> inProgress});

/// Splits unfinished jobs by stage, each stage longest-standing first.
/// Finished jobs are left out.
LiveGroups groupLive(List<Job> jobs) {
  int byTime(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b ? 0 : (a == null ? 1 : -1);
    return a.compareTo(b);
  }

  List<Job> stage(JobStatus status, DateTime? Function(Job) since) =>
      jobs.where((j) => j.status == status).toList()..sort((a, b) => byTime(since(a), since(b)));

  return (
    waiting: stage(JobStatus.open, (j) => j.requestedAt),
    assigned: stage(JobStatus.claimed, (j) => j.claimedAt ?? j.requestedAt),
    inProgress: stage(JobStatus.inProgress, (j) => j.startedAt ?? j.requestedAt),
  );
}

/// Whether [job] is still open after [waitingTooLongAfter].
bool waitingTooLong(Job job, {DateTime? now}) {
  final requested = job.requestedAt;
  if (job.status != JobStatus.open || requested == null) return false;
  return (now ?? DateTime.now()).difference(requested) > waitingTooLongAfter;
}

typedef JobTotals = ({int requested, int done, int cancelled, int billed});

/// Counts for a summary line. `billed` is the total of the finished jobs.
JobTotals summarizeJobs(List<Job> jobs) {
  var done = 0, cancelled = 0, billed = 0;
  for (final job in jobs) {
    if (job.status == JobStatus.done) {
      done++;
      billed += job.total;
    } else if (job.status == JobStatus.cancelled) {
      cancelled++;
    }
  }
  return (requested: jobs.length, done: done, cancelled: cancelled, billed: billed);
}

/// Who cancelled a job, as the end of a sentence; empty when unknown.
String cancelledByLabel(String cancelledBy) => switch (cancelledBy) {
  'customer' => 'by the customer',
  'admin' => 'by the office',
  'system' => 'automatically, no crew accepted in time',
  _ => '',
};

/// The one-line state of a job in a list: "Waiting for crew · 6 min",
/// the crew member's first name with "in progress 18 min", or "Done", when
/// and the total.
String jobStatusLine(Job job, {DateTime? now}) {
  final at = now ?? DateTime.now();
  Duration since(DateTime from) {
    final passed = at.difference(from);
    return passed.isNegative ? Duration.zero : passed;
  }

  final first = firstNameOf(job.crewName);
  final crew = first.isEmpty ? 'Crew' : first;
  final requested = job.requestedAt, claimed = job.claimedAt, started = job.startedAt;
  final completed = job.completedAt, cancelled = job.cancelledAt;
  final line = switch (job.status) {
    JobStatus.open =>
      requested == null ? 'Waiting for crew' : 'Waiting for crew · ${fmtElapsed(since(requested))}',
    JobStatus.claimed =>
      claimed == null ? '$crew · accepted' : '$crew · accepted ${fmtAgo(claimed, now: at)}',
    JobStatus.inProgress =>
      started == null ? '$crew · in progress' : '$crew · in progress ${fmtElapsed(since(started))}',
    JobStatus.done => [
      'Done',
      if (completed != null) fmtDayTime(completed),
      money(job.total),
    ].join(' · '),
    JobStatus.cancelled => ['Cancelled', if (cancelled != null) fmtDayTime(cancelled)].join(' · '),
    JobStatus.unknown => 'Status unknown',
  };
  return job.shovel && job.isActive ? '$line · + shovel' : line;
}

/// A job as a row of a [ListCard]: status bubble, property and address, a
/// status line that keeps time while the job is live, then the crew member's
/// avatar or an OPEN chip.
class JobRow extends StatelessWidget {
  const JobRow(this.job, {super.key, this.onTap, this.meta, this.trailing});
  final Job job;
  final VoidCallback? onTap;

  /// Replaces the status line, for job views that lack the admin's fields.
  final String? meta;

  /// Replaces the avatar / chip.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ticking = switch (job.status) {
      JobStatus.open => job.requestedAt,
      JobStatus.claimed => job.claimedAt,
      JobStatus.inProgress => job.startedAt,
      _ => null,
    };
    if (meta != null || ticking == null) return _row();
    return RElapsed(since: ticking, builder: (_, _) => _row());
  }

  Widget _row() {
    final late = waitingTooLong(job);
    final (bubbleBg, bubbleFg, icon) = switch (job.status) {
      JobStatus.open =>
        late
            ? (RColors.amberTint, RColors.amber, Icons.hourglass_top_rounded)
            : (RColors.paper2, RColors.inkMuted, Icons.hourglass_top_rounded),
      JobStatus.claimed => (RColors.tealTint, RColors.tealDeep, Icons.person_rounded),
      JobStatus.inProgress => (RColors.lime, RColors.ink, Icons.ac_unit_rounded),
      JobStatus.done => (RColors.tealTint, RColors.tealDeep, Icons.check_rounded),
      JobStatus.cancelled => (RColors.dangerTint, RColors.danger, Icons.close_rounded),
      JobStatus.unknown => (RColors.paper2, RColors.inkMuted, Icons.help_outline_rounded),
    };
    final metaColor = switch (job.status) {
      JobStatus.open => late ? amberInk : RColors.inkMuted,
      JobStatus.claimed || JobStatus.inProgress => RColors.tealDeep,
      JobStatus.cancelled => RColors.danger,
      _ => RColors.inkMuted,
    };
    final end = trailing ?? _defaultTrailing();
    return ListRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: bubbleBg, shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: bubbleFg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  job.propertyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: RColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  job.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkMuted),
                ),
                const SizedBox(height: 3),
                Text(
                  meta ?? jobStatusLine(job),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: meta == null ? metaColor : RColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (end != null) ...[const SizedBox(width: 8), end],
        ],
      ),
    );
  }

  Widget? _defaultTrailing() {
    if (job.status == JobStatus.open) {
      return const RChip('OPEN', bg: RColors.amberTint, fg: amberInk);
    }
    final hasCrew = job.crewName.isNotEmpty || job.crewInitials.isNotEmpty;
    final owing = needsPayment(job);
    if (!hasCrew && !owing) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (owing) RPaymentPill(job.payment),
        if (owing && hasCrew) const SizedBox(width: 6),
        if (hasCrew)
          RAvatar(
            job.crewInitials,
            colorKey: job.crewColor.isEmpty ? 'paper' : job.crewColor,
            size: 26,
          ),
      ],
    );
  }
}

/// The steps a job went through, for [JobTimeline]. A cancelled job lists
/// what it reached and ends on "Cancelled".
List<RStep> timelineSteps(Job job, {DateTime? now}) {
  String? when(DateTime? at) => at == null ? null : fmtDayTime(at);
  String? line(List<String?> parts) {
    final shown = [
      for (final part in parts)
        if (part != null && part.isNotEmpty) part,
    ];
    return shown.isEmpty ? null : shown.join(' · ');
  }

  final source = switch (job.source) {
    'admin' => 'by the office',
    'customer' => 'by the customer',
    _ => null,
  };
  final requested = line([when(job.requestedAt), source]);
  final assigned = line([job.crewName, when(job.claimedAt)]);

  if (job.status == JobStatus.cancelled) {
    return [
      RStep('Requested', subtitle: requested, state: RStepState.done),
      if (job.claimedAt != null) RStep('Crew assigned', subtitle: assigned, state: RStepState.done),
      if (job.startedAt != null)
        RStep('Work started', subtitle: when(job.startedAt), state: RStepState.done),
      RStep(
        'Cancelled',
        subtitle: line([when(job.cancelledAt), cancelledByLabel(job.cancelledBy)]),
        state: RStepState.current,
      ),
    ];
  }

  final reached = job.stepIndex;
  RStepState state(int step) => reached == 3 || step < reached
      ? RStepState.done
      : (step == reached ? RStepState.current : RStepState.upcoming);

  final started = job.startedAt;
  String? running;
  if (job.status == JobStatus.inProgress && started != null) {
    final passed = (now ?? DateTime.now()).difference(started);
    running = 'for ${fmtElapsed(passed.isNegative ? Duration.zero : passed)}';
  }
  final took = job.duration;
  return [
    RStep('Requested', subtitle: requested, state: state(0)),
    RStep(
      'Crew assigned',
      subtitle: job.status == JobStatus.open ? 'Open to all approved crew' : assigned,
      state: state(1),
    ),
    RStep(
      'In progress',
      subtitle: line([if (started != null) 'Started ${fmtTime(started)}', running]),
      state: state(2),
    ),
    RStep(
      'Done',
      subtitle: line([when(job.completedAt), if (took != null) 'took ${fmtDuration(took)}']),
      state: state(3),
    ),
  ];
}

/// The job's progress as a vertical tracker; keeps time while work is under
/// way.
class JobTimeline extends StatelessWidget {
  const JobTimeline(this.job, {super.key});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final started = job.startedAt;
    if (job.status == JobStatus.inProgress && started != null) {
      return RElapsed(
        since: started,
        builder: (_, _) => RStepTracker(steps: timelineSteps(job)),
      );
    }
    return RStepTracker(steps: timelineSteps(job));
  }
}

/// What the customer pays for a job, what the crew member earns and what is
/// left.
class AmountRows extends StatelessWidget {
  const AmountRows(this.job, {super.key});
  final Job job;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      KeyValueRow('Plough', money(job.price)),
      if (job.shovel) KeyValueRow('Shovelling', money(job.shovelPrice)),
      KeyValueRow('Customer total', money(job.total), strong: true),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 0.6, thickness: 0.6, color: RColors.borderSoft),
      ),
      KeyValueRow(job.shovel ? 'Crew pay, with shovelling bonus' : 'Crew pay', money(job.crewPay)),
      KeyValueRow(
        'Margin',
        money(job.total - job.crewPay),
        strong: true,
        valueColor: RColors.tealDeep,
      ),
    ],
  );
}
