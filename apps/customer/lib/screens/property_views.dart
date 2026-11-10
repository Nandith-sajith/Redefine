// What the home screen shows under the property strip, one view per state of
// the selected property.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../logic.dart';
import '../widgets.dart';

TextStyle _lead() =>
    GoogleFonts.plusJakartaSans(fontSize: 13.5, color: RColors.inkMuted, height: 1.5);

// ---- No properties ---------------------------------------------------------

class EmptyPropertiesView extends StatelessWidget {
  const EmptyPropertiesView({super.key, required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 44, 32, 40),
    child: Column(
      children: [
        Icon(Icons.add_home_outlined, size: 96, color: RColors.teal.withValues(alpha: 0.45)),
        const SizedBox(height: 16),
        Text('Snow cleared, on demand', style: RText.h1, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          "Add your driveway and we'll visit to give you a fixed price per plough.\n"
          'When it snows, request a plough and the next available crew clears it.',
          textAlign: TextAlign.center,
          style: _lead(),
        ),
        const SizedBox(height: 22),
        RPrimaryButton('Add your first property', icon: Icons.add, onPressed: onAdd),
      ],
    ),
  );
}

// ---- Quote requested -------------------------------------------------------

class QuoteWaitingView extends StatelessWidget {
  const QuoteWaitingView({super.key, required this.property});
  final Property property;

  @override
  Widget build(BuildContext context) {
    final requested = property.createdAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RChip('Quote requested', icon: Icons.schedule, iconColor: RColors.inkMuted),
        const SizedBox(height: 14),
        Text('Your quote is on the way', style: RText.h1),
        const SizedBox(height: 8),
        Text(
          "We'll come by to look at your driveway and send you a price per plough.",
          style: _lead(),
        ),
        const SizedBox(height: 20),
        RCard(
          radius: 18,
          padding: const EdgeInsets.all(18),
          child: RStepTracker(
            steps: [
              RStep(
                'Request sent',
                subtitle: requested == null ? null : fmtDayTime(requested),
                state: RStepState.done,
              ),
              const RStep('We visit and price your driveway', state: RStepState.current),
              const RStep('Quote ready', state: RStepState.upcoming),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.autorenew_rounded, size: 14, color: RColors.inkMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text('This screen updates when your quote is ready.', style: RText.muted),
            ),
          ],
        ),
        if (property.note.isNotEmpty) ...[
          const SizedBox(height: 20),
          const RSectionLabel('Your notes for the crew'),
          const SizedBox(height: 6),
          Text(property.note, style: RText.body.copyWith(height: 1.5)),
        ],
      ],
    );
  }
}

// ---- Quoted ----------------------------------------------------------------

enum _QuoteAction { accept, decline }

class QuoteReceivedView extends StatefulWidget {
  const QuoteReceivedView({
    super.key,
    required this.property,
    required this.price,
    required this.account,
    required this.onChanged,
    required this.onRefresh,
  });

  final Property property;

  /// The quoted price per plough.
  final int price;
  final Account account;

  /// Called with the property as the server returned it after the decision.
  final ValueChanged<Property> onChanged;
  final VoidCallback onRefresh;

  @override
  State<QuoteReceivedView> createState() => _QuoteReceivedViewState();
}

class _QuoteReceivedViewState extends State<QuoteReceivedView> with BusyState {
  _QuoteAction? _action;

  // The quote was re-sent, or answered from another device.
  bool _quoteMoved(ApiException e) {
    if (e.code != 'quote_not_open') return false;
    widget.onRefresh();
    if (mounted) showRSnack(context, 'This quote has changed. Showing the latest.');
    return true;
  }

  Future<void> _accept() async {
    final onChanged = widget.onChanged;
    setState(() => _action = _QuoteAction.accept);
    final result = await run(
      () => api.acceptQuote(widget.property.quoteId),
      success: 'Quote accepted. Request a plough whenever it snows.',
      onError: _quoteMoved,
    );
    if (result != null) onChanged(result.property);
  }

  Future<void> _decline() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Decline this quote?',
      message:
          "We won't plough ${widget.property.name} at this price. "
          'You can ask for a new quote later.',
      confirmLabel: 'Decline quote',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final onChanged = widget.onChanged;
    setState(() => _action = _QuoteAction.decline);
    final result = await run(
      () => api.declineQuote(widget.property.quoteId),
      success: 'Quote declined.',
      onError: _quoteMoved,
    );
    if (result != null) onChanged(result.property);
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RPill('Quote ready', dot: RColors.teal),
        const SizedBox(height: 12),
        Text('Your price is in', style: RText.h1),
        const SizedBox(height: 6),
        Text(
          'We looked at your driveway. Accept the quote to start requesting ploughs.',
          style: _lead(),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            color: RColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: RColors.teal, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Snow ploughing',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: RColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(widget.price),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: RColors.teal,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('per plough', style: RText.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F8F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Shovelling walkways and steps: '
                  '${shovelExtra(account.settings.shovelPrice)} when you want it',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: RColors.ink,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const RSectionLabel('How it works'),
              const SizedBox(height: 8),
              const _Point('Request a plough whenever it snows. There is no schedule to keep.'),
              const SizedBox(height: 6),
              _Point(
                account.paysByCard
                    ? "A hold is placed on your card when you request, and you're "
                          'charged only when the job is done.'
                    : "You're billed after each job.",
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: ROutlineButton(
                      'Decline',
                      color: RColors.inkMuted,
                      fullWidth: true,
                      busy: busy && _action == _QuoteAction.decline,
                      onPressed: busy ? null : _decline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RPrimaryButton(
                      'Accept quote',
                      busy: busy && _action == _QuoteAction.accept,
                      onPressed: busy ? null : _accept,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 3),
        child: Icon(Icons.check_circle_outline_rounded, size: 14, color: RColors.teal),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: RText.muted.copyWith(color: const Color(0xFF555555), height: 1.45),
        ),
      ),
    ],
  );
}

// ---- Declined --------------------------------------------------------------

class DeclinedView extends StatefulWidget {
  const DeclinedView({
    super.key,
    required this.property,
    required this.onChanged,
    required this.onRefresh,
  });

  final Property property;
  final ValueChanged<Property> onChanged;
  final VoidCallback onRefresh;

  @override
  State<DeclinedView> createState() => _DeclinedViewState();
}

class _DeclinedViewState extends State<DeclinedView> with BusyState {
  Future<void> _askAgain() async {
    final onChanged = widget.onChanged;
    final result = await run(
      () => api.requestQuoteAgain(widget.property.id),
      success: "New quote requested. We'll be in touch.",
      onError: (e) {
        // No longer declined: show what it is now, with the server's reason.
        if (e.code == 'invalid_state') widget.onRefresh();
        return false;
      },
    );
    if (result != null) onChanged(result.property);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const RChip('Quote declined', icon: Icons.do_not_disturb_alt_outlined),
      const SizedBox(height: 14),
      Text('You declined this quote.', style: RText.h1),
      const SizedBox(height: 8),
      Text(
        "Changed your mind, or something about the driveway is different? Ask and we'll "
        'price it again.',
        style: _lead(),
      ),
      const SizedBox(height: 20),
      RPrimaryButton('Ask for a new quote', busy: busy, onPressed: _askAgain),
    ],
  );
}

// ---- Active, nothing under way --------------------------------------------

class RequestPloughCard extends StatefulWidget {
  const RequestPloughCard({
    super.key,
    required this.property,
    required this.price,
    required this.account,
    required this.onBeforeRequest,
    required this.onRequested,
    required this.onOpenBilling,
    required this.onCardRequired,
    required this.onRefresh,
  });

  final Property property;

  /// The agreed price per plough.
  final int price;
  final Account account;

  /// Reloads [price] and [account] for the confirmation: the server prices
  /// the job from what it has now, not from what this screen loaded. Resolves
  /// to null when there is nothing to confirm after all, because they could
  /// not be reloaded (which it has reported) or the property turned out to
  /// have a request already.
  final Future<RequestTerms?> Function() onBeforeRequest;

  /// Called with the job a request created, which takes this card's place.
  final ValueChanged<Job> onRequested;
  final VoidCallback onOpenBilling;

  /// A card is needed and none is saved: the reload for the confirmation
  /// found that, or the server refused the request for it.
  final VoidCallback onCardRequired;
  final VoidCallback onRefresh;

  @override
  State<RequestPloughCard> createState() => _RequestPloughCardState();
}

class _RequestPloughCardState extends State<RequestPloughCard> with BusyState {
  final _note = TextEditingController();
  bool _shovel = false;

  /// Whether the price is being brought up to date for the confirmation.
  bool _checking = false;
  String? _cardError;

  int get _total => ploughTotal(
    price: widget.price,
    shovel: _shovel,
    shovelPrice: widget.account.settings.shovelPrice,
  );

  @override
  void didUpdateWidget(RequestPloughCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A complaint about the card no longer applies once the card has changed.
    if (widget.account.billing.card?.updatedAt != oldWidget.account.billing.card?.updatedAt) {
      _cardError = null;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool _requestFailed(ApiException e) {
    switch (e.code) {
      case 'card_required':
        widget.onCardRequired();
        return true;
      case 'card_declined' || 'card_auth_required':
        if (mounted) setState(() => _cardError = e.message);
        return true;
      case 'job_active':
        // Already requested, from another device or by the office.
        widget.onRefresh();
        return true;
      default:
        return false;
    }
  }

  Future<void> _request() async {
    if (_checking) return;
    final shown = _total;
    setState(() => _checking = true);
    final terms = await widget.onBeforeRequest();
    if (!mounted) return;
    setState(() => _checking = false);
    if (terms == null) return;
    final billing = terms.account.billing;
    if (billing.needsCard) {
      widget.onCardRequired();
      return;
    }
    final total = ploughTotal(
      price: terms.price,
      shovel: _shovel,
      shovelPrice: terms.account.settings.shovelPrice,
    );
    final confirmed = await confirmDialog(
      context,
      title: 'Request a plough?',
      message: requestConfirmation(total, billing, shownTotal: shown),
      confirmLabel: 'Request plough',
    );
    if (!confirmed || !mounted) return;
    final onRequested = widget.onRequested;
    setState(() => _cardError = null);
    final job = await run(
      () =>
          api.requestJob(propertyId: widget.property.id, shovel: _shovel, note: _note.text.trim()),
      onError: _requestFailed,
    );
    if (job == null) return;
    // The price can still have changed while the confirmation was open.
    if (mounted) {
      showRSnack(context, requestedMessage(job, confirmed: total), error: job.total != total);
    }
    onRequested(job);
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final working = busy || _checking;
    final cardError = _cardError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroCard(
          eyebrow: 'Your price per plough',
          title: money(widget.price),
          footer: const [
            Icon(Icons.ac_unit_rounded, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: _HeroText('Request when it snows. The next available crew takes it.')),
          ],
        ),
        const SizedBox(height: 12),
        RCard(
          radius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add shovelling ${shovelExtra(account.settings.shovelPrice)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: RColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('Walkways and steps', style: RText.muted),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Switch(
                    value: _shovel,
                    activeThumbColor: Colors.white,
                    activeTrackColor: RColors.teal,
                    onChanged: working ? null : (value) => setState(() => _shovel = value),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RTextField(
                label: 'Note for the crew (optional)',
                controller: _note,
                hint: 'Anything they should know today',
                maxLines: 2,
                maxLength: 500,
                enabled: !working,
              ),
              const SizedBox(height: 14),
              DetailRow('Total', value: money(_total), strong: true),
              Text(
                account.paysByCard
                    ? 'Held on your card when you request, charged when the job is done.'
                    : 'Billed after the job.',
                style: RText.muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (cardError != null) ...[
          RBanner(
            cardError,
            error: true,
            actionLabel: 'Update card',
            onAction: widget.onOpenBilling,
          ),
          const SizedBox(height: 12),
        ],
        if (account.billing.needsCard) ...[
          const RBanner('Add a card to request ploughs', icon: Icons.credit_card_outlined),
          const SizedBox(height: 10),
          RPrimaryButton(
            'Add a card',
            icon: Icons.credit_card_outlined,
            onPressed: widget.onOpenBilling,
          ),
        ] else
          RPrimaryButton(
            'Request plough · ${money(_total)}',
            icon: Icons.ac_unit_rounded,
            busy: working,
            onPressed: _request,
          ),
      ],
    );
  }
}

// ---- Active, job under way -------------------------------------------------

class JobTrackerCard extends StatefulWidget {
  const JobTrackerCard({
    super.key,
    required this.job,
    required this.onCancelled,
    required this.onRefresh,
  });

  final Job job;

  /// Called with the job as its cancellation returned it; this card then
  /// makes way for the next request.
  final ValueChanged<Job> onCancelled;
  final VoidCallback onRefresh;

  @override
  State<JobTrackerCard> createState() => _JobTrackerCardState();
}

class _JobTrackerCardState extends State<JobTrackerCard> with BusyState {
  Future<void> _cancel() async {
    final job = widget.job;
    final confirmed = await confirmDialog(
      context,
      title: 'Cancel this request?',
      message: job.payment.status == PaymentStatus.authorized
          ? 'The hold of ${money(job.total)} on your card will be released.'
          : "You won't be billed for it.",
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final onCancelled = widget.onCancelled;
    final result = await run(
      () => api.cancelJob(job.id),
      onError: (e) {
        if (e.code != 'job_started') return false;
        widget.onRefresh();
        if (mounted) {
          showRSnack(context, "The crew has already started, so this can't be cancelled now.");
        }
        return true;
      },
    );
    if (result != null) onCancelled(result);
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final requested = job.requestedAt;
    final started = job.startedAt;
    final inProgress = job.status == JobStatus.inProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroCard(
          eyebrow: requested == null
              ? 'Plough requested'
              : 'Plough requested · ${fmtDayTime(requested)}',
          title: jobStatusLabel(job.status),
          footer: job.crewName.isEmpty
              ? const [
                  Icon(Icons.groups_2_outlined, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: _HeroText('Open to the next available crew')),
                ]
              : [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      job.crewInitials,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _HeroText('${job.crewName} is your crew')),
                ],
        ),
        const SizedBox(height: 12),
        RCard(
          radius: 18,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RServiceTag(shovel: job.shovel),
              const SizedBox(height: 16),
              if (inProgress && started != null)
                RElapsed(
                  since: started,
                  builder: (_, elapsed) => RStepTracker(steps: jobSteps(job, elapsed: elapsed)),
                )
              else
                RStepTracker(steps: jobSteps(job)),
              const SizedBox(height: 14),
              const RowDivider(),
              DetailRow('Total', value: money(job.total), strong: true),
              Text(activePaymentLine(job.payment), style: RText.muted),
              if (job.note.isNotEmpty) ...[
                const SizedBox(height: 14),
                const RSectionLabel('Your note'),
                const SizedBox(height: 4),
                Text(job.note, style: RText.body.copyWith(height: 1.5)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (job.canCustomerCancel)
          ROutlineButton(
            'Cancel request',
            color: RColors.danger,
            fullWidth: true,
            busy: busy,
            onPressed: _cancel,
          )
        else if (inProgress)
          Center(
            child: Text(
              "The crew is working, so this request can't be cancelled now.",
              textAlign: TextAlign.center,
              style: RText.muted,
            ),
          ),
      ],
    );
  }
}

// ---- Past ploughs ----------------------------------------------------------

class PastPloughs extends StatelessWidget {
  const PastPloughs({super.key, required this.controller, required this.onOpen});

  /// The selected property's jobs, newest first.
  final RLiveController<List<Job>> controller;
  final ValueChanged<Job> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const RSectionLabel('Past ploughs'),
      const SizedBox(height: 4),
      LiveSection<List<Job>>(
        controller: controller,
        builder: (context, jobs) {
          final past = pastJobs(jobs);
          if (past.isEmpty) {
            return const REmptyState(
              icon: Icons.ac_unit_rounded,
              title: 'No ploughs yet.',
              message: 'Finished and cancelled requests are listed here.',
            );
          }
          return Column(
            children: [
              for (var i = 0; i < past.length; i++)
                _PastPloughRow(past[i], divided: i > 0, onTap: () => onOpen(past[i])),
            ],
          );
        },
      ),
    ],
  );
}

class _PastPloughRow extends StatelessWidget {
  const _PastPloughRow(this.job, {required this.divided, required this.onTap});
  final Job job;
  final bool divided;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = job.status == JobStatus.done;
    final date = pastJobDate(job);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: divided
              ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: done ? RColors.tealTint : RColors.paper2,
              ),
              child: Icon(
                done ? serviceIcon(shovel: job.shovel) : Icons.close_rounded,
                size: 20,
                color: done ? RColors.tealDeep : RColors.inkMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date == null ? serviceLabel(shovel: job.shovel) : fmtDay(date),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: RColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pastJobSummary(job),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RText.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (done) ...[
                  Text(money(job.total), style: RText.title),
                  const SizedBox(height: 4),
                ],
                JobPaymentPill(job),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }
}

// ---- Anything else ---------------------------------------------------------

/// For a property in a state this version of the app does not know.
class UnavailablePropertyView extends StatelessWidget {
  const UnavailablePropertyView({super.key, required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => REmptyState(
    icon: Icons.help_outline_rounded,
    title: "This property can't be shown right now.",
    message: 'Refreshing usually sorts it out.',
    action: ROutlineButton('Refresh', icon: Icons.refresh_rounded, onPressed: onRefresh),
  );
}

// ---- Shared pieces ---------------------------------------------------------

/// The deep-teal headline card: an eyebrow line, a large title, and a footer
/// row under a hairline.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.eyebrow, required this.title, required this.footer});
  final String eyebrow, title;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: RColors.tealDeep, borderRadius: BorderRadius.circular(18)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
          ),
          child: Row(children: footer),
        ),
      ],
    ),
  );
}

class _HeroText extends StatelessWidget {
  const _HeroText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.92)),
  );
}
