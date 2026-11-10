import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../crew_data.dart';
import '../job_actions.dart';
import '../launch.dart';
import '../logic.dart';
import '../widgets.dart';

/// Opens a job's page. When the page closes with something to say ("Job
/// released", "Job complete · …") the message is shown on the screen below.
Future<void> openJobDetail(
  BuildContext context,
  CrewData data, {
  required String jobId,
  Job? initial,
}) async {
  final message = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => CrewJobDetailScreen(jobId: jobId, data: data, initial: initial),
    ),
  );
  if (message != null && context.mounted) showRSnack(context, message);
}

/// One job, from the open request to the finished plough, with the action
/// that fits its status: accept, start or release, complete.
class CrewJobDetailScreen extends StatefulWidget {
  const CrewJobDetailScreen({super.key, required this.jobId, required this.data, this.initial});
  final String jobId;
  final CrewData data;

  /// The job as the list showed it, so the page opens without a spinner.
  final Job? initial;

  @override
  State<CrewJobDetailScreen> createState() => _CrewJobDetailScreenState();
}

enum _Action { accept, start, release, complete }

class _CrewJobDetailScreenState extends State<CrewJobDetailScreen>
    with BusyState<CrewJobDetailScreen>, JobActions<CrewJobDetailScreen> {
  /// Null data: the server no longer shows this job to this crew member.
  late final RLiveController<Job?> _job = RLiveController<Job?>(_load);
  final _note = TextEditingController();

  /// The job as last seen, kept when it disappears.
  Job? _seen;
  _Action? _running;

  /// Whether the crew member asked to release the job since it became theirs.
  /// From then on, finding it open again is their own doing, even when the
  /// server's answer to the release never arrived.
  bool _releaseAsked = false;

  @override
  CrewData get crewData => widget.data;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _seen = initial;
      _job.setData(initial);
    }
    _job.addListener(_onJobChanged);
  }

  @override
  void dispose() {
    _job.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<Job?> _load() async {
    try {
      return await guardCrew(() => api.job(widget.jobId));
    } on ApiException catch (e) {
      // Crew only see open jobs and their own: this one is neither any more.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  void _onJobChanged() {
    final job = _job.data;
    if (job == null) return;
    final before = _seen;
    _seen = job;
    if (mounted &&
        _running == null &&
        !_releaseAsked &&
        before?.status == JobStatus.claimed &&
        job.status == JobStatus.open) {
      showRSnack(context, 'The office put this job back on the open list.');
    }
  }

  /// Runs one of the job actions with its button busy and shows the job as
  /// the server returned it. A refusal has already been explained by then;
  /// the page reloads to show where the job stands.
  Future<Job?> _perform(_Action action, Future<Job?> Function() call) async {
    if (busy) return null;
    setState(() => _running = action);
    final job = await call();
    if (!mounted) return job;
    if (job == null) {
      _job.refresh(silent: true);
    } else {
      // Taken over while the action still counts as running: the change is
      // the page's own. A reload that was under way is older and is dropped,
      // so it cannot turn up later looking like someone else's doing.
      _job.setData(job);
    }
    setState(() => _running = null);
    return job;
  }

  Future<void> _accept() async {
    final job = await _perform(_Action.accept, () => acceptJob(widget.jobId));
    if (job == null || !mounted) return;
    _releaseAsked = false;
    // Back now leads to the Jobs tab, where the job is listed.
    widget.data.goTo(CrewTab.jobs);
  }

  void _start() => _perform(_Action.start, () => startJob(widget.jobId));

  Future<void> _release() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Release this job?',
      message: 'It goes back to the open list, where any crew member can accept it.',
      confirmLabel: 'Release job',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final job = await _perform(_Action.release, () {
      _releaseAsked = true;
      return releaseJob(widget.jobId);
    });
    if (job != null && mounted) Navigator.of(context).pop('Job released');
  }

  Future<void> _complete(Job current) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Mark this job complete?',
      message:
          'Confirm that the work is finished: ${workLabel(shovel: current.shovel).toLowerCase()}. '
          '${money(current.crewPay)} is added to your pay.',
      confirmLabel: 'Mark complete',
      cancelLabel: 'Not yet',
    );
    if (!confirmed || !mounted) return;
    final job = await _perform(
      _Action.complete,
      () => completeJob(widget.jobId, note: _note.text.trim()),
    );
    if (job == null || !mounted) return;
    // A job page always sits directly on the shell, so this lands on a tab.
    Navigator.of(context).pop('Job complete · ${money(job.crewPay)} added to your pay');
  }

  // Launched straight from the tap, or browsers block the new tab.
  void _directions(Job job) => openDirections(job.address).then((opened) {
    if (!opened && mounted) {
      showRSnack(context, "Couldn't open maps on this device.", error: true);
    }
  });

  void _call(Job job) => callPhone(job.customerPhone).then((result) {
    if (!mounted) return;
    final phone = job.customerPhone;
    switch (result) {
      case CallResult.dialling:
        break;
      case CallResult.unconfirmedCopied:
        showRSnack(context, '$phone copied to the clipboard, in case no phone app opens.');
      case CallResult.unconfirmed:
        showRSnack(context, 'If no phone app opens, dial $phone.');
      case CallResult.copied:
        showRSnack(context, 'No phone app here. $phone copied to the clipboard.');
      case CallResult.failed:
        showRSnack(context, "Couldn't start a call here. Dial $phone.", error: true);
    }
  });

  void _back() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _job,
          builder: (context, _) {
            final job = _job.data;
            // A finished job no longer changes by itself; pull to refresh.
            final polls = job?.isActive ?? !_job.hasData;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: [
                      RBackRow('Back', onTap: _back),
                      const Spacer(),
                      if (job != null) CrewStatusPill(job),
                    ],
                  ),
                ),
                Expanded(
                  child: RLive<Job?>(
                    controller: _job,
                    pollEvery: polls ? const Duration(seconds: 10) : null,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    builder: (context, job) => job == null ? _gone() : _content(job),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _gone() => REmptyState(
    icon: Icons.event_busy_rounded,
    title: 'This job is no longer available',
    message: _seen == null || _seen!.status == JobStatus.open
        ? 'Another crew member took it, or the request was cancelled.'
        : 'It is no longer assigned to you.',
    action: ROutlineButton('Back', icon: Icons.chevron_left, onPressed: _back),
  );

  Widget _content(Job job) {
    final cancelled = job.status == JobStatus.cancelled;
    final done = job.status == JobStatus.done;
    final mineNow = job.status == JobStatus.claimed || job.status == JobStatus.inProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(job.propertyName, style: RText.h1),
        const SizedBox(height: 4),
        Text(
          jobStatusLine(job),
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted),
        ),
        const SizedBox(height: 12),
        if (!cancelled) ...[
          Text(
            '${done ? 'You earned' : 'You earn'} ${money(job.crewPay)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: RColors.teal,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RServiceTag(shovel: job.shovel),
            if (done) PaidOutChip(paidOut: job.paidOut),
          ],
        ),
        if (cancelled) ...[
          const SizedBox(height: 14),
          RBanner(
            '${cancelledByLabel(job)}. There is nothing more to do for this job.',
            error: true,
            icon: Icons.event_busy_rounded,
          ),
        ],
        const SizedBox(height: 14),
        _AddressCard(job, onDirections: () => _directions(job)),
        if (job.customerName.isNotEmpty) ...[
          const SizedBox(height: 14),
          const RSectionLabel('Customer'),
          const SizedBox(height: 8),
          _CustomerCard(job, onCall: mineNow ? () => _call(job) : null),
        ],
        if (job.note.isNotEmpty) ...[
          const SizedBox(height: 14),
          const RSectionLabel('Note from the customer'),
          const SizedBox(height: 8),
          _NoteCard(job.note),
        ],
        ...switch (job.status) {
          JobStatus.open => _openActions(),
          JobStatus.claimed => _claimedActions(),
          JobStatus.inProgress => _inProgressActions(job),
          JobStatus.done => _doneSummary(job),
          JobStatus.cancelled || JobStatus.unknown => const <Widget>[],
        },
      ],
    );
  }

  List<Widget> _openActions() => [
    const SizedBox(height: 14),
    const RBanner('Open to every approved crew member. The first to accept takes the job.'),
    const SizedBox(height: 20),
    RPrimaryButton(
      'Accept job',
      icon: Icons.check_rounded,
      busy: _running == _Action.accept,
      onPressed: busy ? null : _accept,
    ),
  ];

  List<Widget> _claimedActions() => [
    const SizedBox(height: 20),
    RPrimaryButton(
      'Start work',
      icon: Icons.play_arrow_rounded,
      busy: _running == _Action.start,
      onPressed: busy ? null : _start,
    ),
    const SizedBox(height: 10),
    ROutlineButton(
      'Release job',
      color: RColors.danger,
      fullWidth: true,
      busy: _running == _Action.release,
      onPressed: busy ? null : _release,
    ),
  ];

  List<Widget> _inProgressActions(Job job) => [
    const SizedBox(height: 18),
    RTextField(
      label: 'Note for the customer (optional)',
      hint: 'Anything they should know about the job',
      controller: _note,
      maxLines: 3,
      maxLength: 500,
      enabled: !busy,
    ),
    const SizedBox(height: 18),
    RPrimaryButton(
      'Mark complete',
      icon: Icons.check_rounded,
      busy: _running == _Action.complete,
      onPressed: busy ? null : () => _complete(job),
    ),
  ];

  List<Widget> _doneSummary(Job job) {
    final duration = job.duration;
    final completedAt = job.completedAt;
    return [
      const SizedBox(height: 14),
      const RSectionLabel('Summary'),
      const SizedBox(height: 8),
      RCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            if (completedAt != null) _SummaryRow('Completed', fmtDayTime(completedAt)),
            if (duration != null) _SummaryRow('Time on site', fmtDuration(duration)),
            _SummaryRow(
              'Pay',
              job.paidOut
                  ? '${money(job.crewPay)} · paid out'
                  : '${money(job.crewPay)} · in your unpaid balance',
            ),
          ],
        ),
      ),
      if (job.crewNote.isNotEmpty) ...[
        const SizedBox(height: 14),
        const RSectionLabel('Your note to the customer'),
        const SizedBox(height: 8),
        _NoteCard(job.crewNote),
      ],
    ];
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard(this.job, {required this.onDirections});
  final Job job;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) => RCard(
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined, size: 18, color: RColors.teal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.address,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: RColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(workLabel(shovel: job.shovel), style: RText.muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ROutlineButton(
          'Get directions',
          icon: Icons.navigation_outlined,
          fullWidth: true,
          onPressed: onDirections,
        ),
      ],
    ),
  );
}

/// Who the job is for. Crew only learn this once the job is theirs.
class _CustomerCard extends StatelessWidget {
  const _CustomerCard(this.job, {required this.onCall});
  final Job job;

  /// Null once the job is over: there is no reason left to call.
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final onCall = this.onCall;
    final hasPhone = job.customerPhone.isNotEmpty;
    return RCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              RAvatar(job.customerInitials, colorKey: 'teal'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.customerName,
                      style: RText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasPhone) ...[
                      const SizedBox(height: 2),
                      Text(job.customerPhone, style: RText.muted),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasPhone && onCall != null) ...[
            const SizedBox(height: 12),
            ROutlineButton(
              'Call customer',
              icon: Icons.phone_outlined,
              fullWidth: true,
              onPressed: onCall,
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: RCard(
      radius: 14,
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: const Color(0xFF444444),
          height: 1.55,
        ),
      ),
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Text(label, style: RText.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: RColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
