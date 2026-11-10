// Pure helpers behind the crew screens: grouping, wording and dates. Nothing
// here touches the network or the widget tree.

import 'package:redefine_ui/redefine_ui.dart';

/// The signed-in crew member's jobs, split the way the Jobs tab shows them.
class MyJobs {
  const MyJobs({required this.inProgress, required this.accepted, required this.recent});

  /// Started and not finished, earliest start first.
  final List<Job> inProgress;

  /// Accepted and not started, longest-waiting customer first.
  final List<Job> accepted;

  /// Done or cancelled, latest first.
  final List<Job> recent;

  int get toDo => inProgress.length + accepted.length;

  bool get isEmpty => toDo == 0 && recent.isEmpty;
}

MyJobs groupMine(List<Job> jobs) {
  List<Job> pick(bool Function(Job) test, int Function(Job, Job) order) =>
      jobs.where(test).toList()..sort(order);
  return MyJobs(
    inProgress: pick((j) => j.status == JobStatus.inProgress, _byTime((j) => j.startedAt)),
    accepted: pick((j) => j.status == JobStatus.claimed, _byTime((j) => j.requestedAt)),
    recent: pick(
      (j) => j.status == JobStatus.done || j.status == JobStatus.cancelled,
      _byTime(finishedAt, latestFirst: true),
    ),
  );
}

/// When a job ended: completed, or else cancelled.
DateTime? finishedAt(Job job) => job.completedAt ?? job.cancelledAt;

// Jobs without the timestamp go last either way.
int Function(Job, Job) _byTime(DateTime? Function(Job) at, {bool latestFirst = false}) => (a, b) {
  final ta = at(a), tb = at(b);
  if (ta == null || tb == null) return ta == null ? (tb == null ? 0 : 1) : -1;
  return latestFirst ? tb.compareTo(ta) : ta.compareTo(tb);
};

/// `1 job`, `3 jobs`.
String countLabel(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : plural ?? '${singular}s'}';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Monday, Oct 5`, in the device's local time.
String longDate(DateTime date) {
  final d = date.toLocal();
  return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

/// The line under the date on the Jobs tab. [pay] is null until it has loaded.
String homeSummary(MyJobs jobs, CrewPay? pay) {
  final toDo = jobs.toDo == 0 ? 'Nothing to do' : '${jobs.toDo} to do';
  return pay == null ? toDo : '$toDo · ${money(pay.earnedToday)} earned today';
}

/// Everything "earned today" depends on, as far as the crew member's own
/// [jobs] show it: the local day and which jobs are done. While this stays
/// the same, the figure in the pay summary cannot have changed.
String earningsKey(List<Job> jobs, DateTime now) {
  final day = now.toLocal();
  final done = [
    for (final job in jobs)
      if (job.status == JobStatus.done) job.id,
  ]..sort();
  return '${day.year}-${day.month}-${day.day}|${done.join(',')}';
}

/// The crew member's own jobs once an action returned [job]: with it on top,
/// as the job with the latest activity, or without it when it was released.
List<Job> mineAfter(List<Job> mine, Job job) => [
  if (job.status != JobStatus.open) job,
  for (final other in mine)
    if (other.id != job.id) other,
];

/// The open requests once an action returned [job] as taken: without it.
/// Null when the list does not change.
List<Job>? openAfter(List<Job> open, Job job) =>
    job.status == JobStatus.open || open.every((other) => other.id != job.id)
    ? null
    : [
        for (final other in open)
          if (other.id != job.id) other,
      ];

/// A job status in the crew's words (the shared pill speaks to customers).
String crewStatusLabel(JobStatus status) => switch (status) {
  JobStatus.open => 'Open',
  JobStatus.claimed => 'Accepted',
  JobStatus.inProgress => 'In progress',
  JobStatus.done => 'Done',
  JobStatus.cancelled => 'Cancelled',
  JobStatus.unknown => 'Unknown',
};

String cancelledByLabel(Job job) => switch (job.cancelledBy) {
  'customer' => 'Cancelled by the customer',
  'admin' => 'Cancelled by the office',
  _ => 'Cancelled',
};

/// What there is to do on site.
String workLabel({required bool shovel}) =>
    shovel ? 'Plough the driveway, shovel the walkways and steps' : 'Plough the driveway';

/// Where the job stands and since when, for the line under its title:
/// `Requested 6 min ago`, `Completed · Oct 2, 9:42 am`.
String jobStatusLine(Job job, {DateTime? now}) {
  String since(String what, DateTime? at) => at == null ? what : '$what ${fmtAgo(at, now: now)}';
  String on(String what, DateTime? at) => at == null ? what : '$what · ${fmtDayTime(at)}';
  return switch (job.status) {
    JobStatus.open || JobStatus.unknown => since('Requested', job.requestedAt),
    JobStatus.claimed => since('Accepted', job.claimedAt),
    JobStatus.inProgress => on('Started', job.startedAt),
    JobStatus.done => on('Completed', job.completedAt),
    JobStatus.cancelled => on(cancelledByLabel(job), job.cancelledAt),
  };
}
