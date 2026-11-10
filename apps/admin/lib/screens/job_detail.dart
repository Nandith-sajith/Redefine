import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';
import '../widgets/job_widgets.dart';
import 'crew_member.dart';
import 'customer_detail.dart';

enum _Action { cancel, complete, reopen, markPaid, retryCharge, openCrew }

/// Whether [job] can still change without the office doing anything: it is
/// live, or it is over and its card hold has yet to be charged or released.
bool jobStillChanging(Job job) => job.isActive || job.payment.status == PaymentStatus.authorized;

/// Where the payment of [job] stands, in a sentence. The same payment status
/// reads differently once the job is over: a cancelled job is never billed,
/// and a hold that outlives its job is on its way to being charged or
/// released.
String paymentExplanation(Job job) {
  final payment = job.payment;
  final total = money(job.total);
  final captured = payment.capturedAt;
  return switch (payment.status) {
    PaymentStatus.none =>
      job.status == JobStatus.cancelled
          ? 'The job was cancelled. Nothing was billed.'
          : 'Nothing is billed until the job is done.',
    PaymentStatus.authorized => switch (job.status) {
      JobStatus.cancelled =>
        "The job was cancelled. The hold of $total on the customer's card is being released.",
      JobStatus.done =>
        "The job is done. The charge of $total to the customer's card is being processed.",
      _ => "A hold of $total is on the customer's card. It is charged when the job is done.",
    },
    PaymentStatus.captured =>
      captured == null ? 'Charged $total.' : 'Charged $total on ${fmtDayTime(captured)}.',
    PaymentStatus.released => 'The hold was released. Nothing was charged.',
    PaymentStatus.failed => 'The charge of $total did not go through.',
    PaymentStatus.due => '$total is due from the customer.',
    PaymentStatus.paid => 'Marked as paid by the office.',
    PaymentStatus.unknown => '',
  };
}

/// Everything about one job, and the office's ways to step in: cancel it,
/// complete it for the crew, hand it back to all crew, settle its payment.
class AdminJobDetailScreen extends StatefulWidget {
  const AdminJobDetailScreen({super.key, required this.jobId, this.initial});
  final String jobId;

  /// The job as the previous screen had it (admin view), shown until the
  /// first load lands.
  final Job? initial;

  @override
  State<AdminJobDetailScreen> createState() => _AdminJobDetailScreenState();
}

class _AdminJobDetailScreenState extends State<AdminJobDetailScreen>
    with BusyState<AdminJobDetailScreen> {
  late final RLiveController<Job> _job = RLiveController(() => api.job(widget.jobId));
  _Action? _running;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _job.setData(initial);
    // The poll interval depends on the job's status.
    _job.addListener(_onJob);
  }

  @override
  void dispose() {
    _job.dispose();
    super.dispose();
  }

  void _onJob() {
    if (mounted) setState(() {});
  }

  /// Runs one action on the job and shows the job it returns.
  Future<Job?> _act(_Action action, Future<Job> Function() call) async {
    if (busy) return null;
    setState(() => _running = action);
    final job = await run(
      call,
      onError: (e) {
        // The job has moved on (the crew finished it, the customer cancelled
        // it): show where it stands now, under the server's explanation.
        if (e.statusCode == 409 || e.statusCode == 404) _job.refresh(silent: true);
        return false;
      },
    );
    if (mounted) setState(() => _running = null);
    if (job != null) _job.setData(job);
    return job;
  }

  String _crewName(Job job) => job.crewName.isEmpty ? 'the crew member' : job.crewName;

  Future<void> _cancel(Job job) async {
    final held = job.payment.status == PaymentStatus.authorized;
    final confirmed = await confirmDialog(
      context,
      title: 'Cancel this job?',
      message: [
        if (job.status == JobStatus.inProgress) 'Work has already started.',
        if (job.status == JobStatus.claimed) '${_crewName(job)} has accepted it.',
        held
            ? "The hold of ${money(job.total)} on the customer's card is released."
            : 'The customer is not billed.',
      ].join(' '),
      confirmLabel: 'Cancel job',
      cancelLabel: 'Keep job',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final cancelled = await _act(_Action.cancel, () => api.cancelJob(job.id));
    if (cancelled == null || !mounted) return;
    showRSnack(
      context,
      cancelled.payment.status == PaymentStatus.released
          ? 'Job cancelled · hold released'
          : 'Job cancelled',
    );
  }

  Future<void> _complete(Job job) async {
    final card = job.payment.mode == PaymentMode.stripe;
    final confirmed = await confirmDialog(
      context,
      title: 'Complete this job?',
      message:
          'Use this when the work is done but was not marked complete in the crew app. '
          '${_crewName(job)} earns ${money(job.crewPay)} and the customer is '
          '${card ? 'charged' : 'billed'} ${money(job.total)}.',
      confirmLabel: 'Complete job',
    );
    if (!confirmed || !mounted) return;
    final done = await _act(_Action.complete, () => api.completeJob(job.id));
    if (done == null || !mounted) return;
    if (done.payment.status == PaymentStatus.failed) {
      showRSnack(context, 'Job completed, but the charge failed.', error: true);
    } else {
      showRSnack(context, 'Job completed');
    }
  }

  Future<void> _reopen(Job job) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Return this job to open?',
      message:
          '${_crewName(job)} is taken off the job and every approved crew member can '
          'accept it again.',
      confirmLabel: 'Return to open',
    );
    if (!confirmed || !mounted) return;
    final reopened = await _act(_Action.reopen, () => api.unclaimJob(job.id));
    if (reopened != null && mounted) showRSnack(context, 'Job is open to all crew again');
  }

  Future<void> _markPaid(Job job) async {
    final payer = job.customerName.isEmpty ? 'the customer' : job.customerName;
    final confirmed = await confirmDialog(
      context,
      title: 'Mark as paid?',
      message: 'Record that $payer paid ${money(job.total)} for this plough outside the app.',
      confirmLabel: 'Mark paid',
    );
    if (!confirmed || !mounted) return;
    final paid = await _act(_Action.markPaid, () => api.markJobPaid(job.id));
    if (paid != null && mounted) showRSnack(context, 'Marked as paid · ${money(paid.total)}');
  }

  Future<void> _retryCharge(Job job) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Retry the charge?',
      message: "Try again to charge ${money(job.total)} to the customer's saved card.",
      confirmLabel: 'Retry charge',
    );
    if (!confirmed || !mounted) return;
    final retried = await _act(_Action.retryCharge, () => api.retryJobPayment(job.id));
    if (retried == null || !mounted) return;
    if (retried.payment.status == PaymentStatus.captured) {
      showRSnack(context, 'Charged ${money(retried.total)}');
    } else {
      showRSnack(context, retried.payment.error ?? 'The charge failed again.', error: true);
    }
  }

  /// The job only names its crew member; their page needs the crew record.
  Future<void> _openCrew(Job job) async {
    if (busy) return;
    setState(() => _running = _Action.openCrew);
    final crew = await run(api.crew);
    if (!mounted) return;
    setState(() => _running = null);
    if (crew == null) return;
    final everyone = [...crew.active, ...crew.pending, ...crew.rejected];
    final matches = everyone.where((member) => member.id == job.crewId);
    if (matches.isEmpty) {
      showRSnack(context, 'That crew member is no longer on the crew list.', error: true);
      return;
    }
    await pushScreen<void>(context, CrewMemberScreen(member: matches.first));
  }

  @override
  Widget build(BuildContext context) {
    final current = _job.data;
    return PushedPage(
      child: RLive<Job>(
        controller: _job,
        // A finished job whose payment is settled no longer changes on its own.
        pollEvery: current == null || jobStillChanging(current)
            ? const Duration(seconds: 10)
            : null,
        padding: pagePadding,
        builder: (context, job) => _body(job),
      ),
    );
  }

  Widget _body(Job job) {
    final hasNotes = job.note.isNotEmpty || job.crewNote.isNotEmpty;
    final actions = _actions(job);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            RJobStatusPill(job.status),
            RServiceTag(shovel: job.shovel),
          ],
        ),
        const SizedBox(height: 12),
        Text(job.propertyName, style: RText.h1),
        const SizedBox(height: 4),
        Text(job.address, style: RText.muted),
        const SizedBox(height: 16),
        RCard(child: JobTimeline(job)),
        const SizedBox(height: 18),
        const RSectionLabel('Customer'),
        const SizedBox(height: 8),
        ListCard(
          radius: 14,
          children: [
            ListRow(
              onTap: () =>
                  pushScreen<void>(context, CustomerDetailScreen(customerId: job.customerId)),
              child: PersonRow(
                initials: job.customerInitials,
                colorKey: 'paper',
                name: job.customerName,
                subtitle: job.source == 'admin'
                    ? 'Job created by the office'
                    : 'Requested in the app',
                trailing: rowChevron,
              ),
            ),
            if (job.customerPhone.isNotEmpty)
              ContactRow(icon: Icons.phone_outlined, value: job.customerPhone, what: 'Phone'),
          ],
        ),
        const SizedBox(height: 18),
        const RSectionLabel('Crew'),
        const SizedBox(height: 8),
        _crewCard(job),
        if (hasNotes) ...[
          const SizedBox(height: 18),
          const RSectionLabel('Notes'),
          const SizedBox(height: 8),
          RCard(
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (job.note.isNotEmpty)
                  _Note(
                    from: job.source == 'admin' ? 'From the office' : 'From the customer',
                    text: job.note,
                  ),
                if (job.note.isNotEmpty && job.crewNote.isNotEmpty) const SizedBox(height: 12),
                if (job.crewNote.isNotEmpty) _Note(from: 'From the crew', text: job.crewNote),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        const RSectionLabel('Amounts'),
        const SizedBox(height: 8),
        RCard(radius: 14, child: AmountRows(job)),
        const SizedBox(height: 18),
        const RSectionLabel('Payment'),
        const SizedBox(height: 8),
        _PaymentCard(job),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            actions[i],
          ],
        ],
      ],
    );
  }

  Widget _crewCard(Job job) {
    if (job.crewId.isEmpty) {
      return job.status == JobStatus.open
          ? const RBanner(
              'Open to all approved crew. The first to accept takes it.',
              icon: Icons.groups_outlined,
            )
          : const TextCard('No crew member took this job.');
    }
    return ListCard(
      radius: 14,
      children: [
        ListRow(
          onTap: busy ? null : () => _openCrew(job),
          child: PersonRow(
            initials: job.crewInitials,
            colorKey: job.crewColor,
            name: job.crewName,
            subtitle: job.status == JobStatus.done
                ? 'Earned ${money(job.crewPay)} · ${job.paidOut ? 'paid out' : 'not paid out yet'}'
                : 'Earns ${money(job.crewPay)} for this job',
            trailing: _running == _Action.openCrew
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : rowChevron,
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(Job job) {
    VoidCallback? unlessBusy(VoidCallback action) => busy ? null : action;
    final assigned = job.status == JobStatus.claimed || job.status == JobStatus.inProgress;
    final failedCard =
        job.payment.mode == PaymentMode.stripe && job.payment.status == PaymentStatus.failed;
    return [
      if (assigned)
        RPrimaryButton(
          'Complete job',
          icon: Icons.check_rounded,
          busy: _running == _Action.complete,
          onPressed: unlessBusy(() => _complete(job)),
        ),
      if (job.status == JobStatus.claimed)
        ROutlineButton(
          'Return to open',
          fullWidth: true,
          busy: _running == _Action.reopen,
          onPressed: unlessBusy(() => _reopen(job)),
        ),
      if (job.isActive)
        ROutlineButton(
          'Cancel job',
          fullWidth: true,
          color: RColors.danger,
          busy: _running == _Action.cancel,
          onPressed: unlessBusy(() => _cancel(job)),
        ),
      if (needsPayment(job))
        RPrimaryButton(
          'Mark paid · ${money(job.total)}',
          busy: _running == _Action.markPaid,
          onPressed: unlessBusy(() => _markPaid(job)),
        ),
      if (failedCard)
        ROutlineButton(
          'Retry charge',
          fullWidth: true,
          icon: Icons.refresh_rounded,
          busy: _running == _Action.retryCharge,
          onPressed: unlessBusy(() => _retryCharge(job)),
        ),
    ];
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.from, required this.text});
  final String from, text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(from.toUpperCase(), style: RText.eyebrow),
      const SizedBox(height: 4),
      Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: const Color(0xFF444444),
          height: 1.5,
        ),
      ),
    ],
  );
}

/// How the job is paid for and where that stands.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard(this.job);
  final Job job;

  @override
  Widget build(BuildContext context) {
    final payment = job.payment;
    final explanation = paymentExplanation(job);
    final error = payment.error, expires = payment.holdExpiresAt;
    // Once the job is over the hold is being settled, not waiting to expire.
    final holdWaiting = job.isActive && payment.status == PaymentStatus.authorized;
    return RCard(
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(switch (payment.mode) {
                  PaymentMode.stripe => 'Card on file',
                  PaymentMode.manual => 'Billed manually',
                  PaymentMode.unknown => 'Payment',
                }, style: RText.title),
              ),
              RPaymentPill(payment),
            ],
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(explanation, style: RText.muted.copyWith(height: 1.45)),
          ],
          // The server's own account of what went wrong, whatever the status:
          // a declined charge, or a hold that could not be released yet.
          if (error != null && error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: RText.muted.copyWith(color: RColors.danger, fontWeight: FontWeight.w600),
            ),
          ],
          if (holdWaiting && expires != null) ...[
            const SizedBox(height: 6),
            Text('The hold expires ${fmtDayTime(expires)}.', style: RText.muted),
          ],
        ],
      ),
    );
  }
}
