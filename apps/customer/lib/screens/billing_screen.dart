import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../logic.dart';
import '../widgets.dart';
import 'job_detail.dart';

/// Where a card setup stands on this screen.
enum _Setup {
  /// Not adding a card.
  idle,

  /// The Stripe page is ready; the customer has yet to open it.
  ready,

  /// The Stripe page was opened; watching for the saved card.
  waiting,
}

/// The saved card (in Stripe mode), the balance due and every charge.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> with BusyState, WidgetsBindingObserver {
  static const _checkEvery = Duration(seconds: 3);

  /// Ten minutes of automatic checks.
  static const _maxAutoChecks = 200;

  final _billing = RLiveController<Billing>(() => api.billing());

  _Setup _setup = _Setup.idle;
  Uri? _stripeUrl;

  /// The card on file when the setup began, to tell a new one from it.
  CardInfo? _cardBefore;
  Timer? _timer;
  int _autoChecks = 0;
  bool _autoStopped = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _billing.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Typically the customer coming back from the Stripe tab.
    if (state == AppLifecycleState.resumed && _setup == _Setup.waiting) _quietCheck();
  }

  Future<void> _startSetup() async {
    final url = await run(
      api.createCardSetupSession,
      onError: (e) {
        if (e.code != 'payments_manual') return false;
        // Card payments were switched off after this screen loaded.
        _billing.refresh();
        if (mounted) {
          showRSnack(context, "Cards aren't in use right now. You're billed after each job.");
        }
        return true;
      },
    );
    if (url == null || !mounted) return;
    setState(() {
      _stripeUrl = url;
      _cardBefore = _billing.data?.card;
      _setup = _Setup.ready;
    });
  }

  /// Opens the Stripe page and starts watching for the card. Runs straight
  /// from the tap with nothing awaited first: a browser only lets a click
  /// open a new tab.
  void _openStripe() {
    final url = _stripeUrl;
    if (url == null) return;
    openExternal(url).then<void>((opened) {
      if (!opened) _stripeBlocked();
    }, onError: (Object _) => _stripeBlocked());
    _timer?.cancel();
    _autoChecks = 0;
    _timer = Timer.periodic(_checkEvery, (_) => _autoCheck());
    setState(() {
      _setup = _Setup.waiting;
      _autoStopped = false;
    });
  }

  void _stripeBlocked() {
    if (!mounted) return;
    showRSnack(
      context,
      "Stripe didn't open. Allow pop-ups for this site, then use Open Stripe again.",
      error: true,
    );
  }

  void _autoCheck() {
    if (++_autoChecks > _maxAutoChecks) {
      _timer?.cancel();
      if (mounted) setState(() => _autoStopped = true);
      return;
    }
    _quietCheck();
  }

  /// Re-checks the setup with the server. A failure is not reported: the
  /// screen keeps waiting and the next check tries again.
  Future<void> _quietCheck() async {
    if (_checking || busy) return;
    _checking = true;
    try {
      final fresh = await api.refreshBilling();
      if (mounted && _setup == _Setup.waiting) _cardLanded(fresh, _cardBefore);
    } on ApiException {
      // Still waiting.
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkNow() async {
    final wasWaiting = _setup == _Setup.waiting;
    final before = wasWaiting ? _cardBefore : _billing.data?.card;
    final fresh = await run(api.refreshBilling);
    if (fresh == null || !mounted) return;
    if (wasWaiting && _setup != _Setup.waiting) {
      // An automatic check got there first, or the setup was cancelled.
      _billing.setData(fresh);
    } else if (!_cardLanded(fresh, before)) {
      showRSnack(context, 'No new card yet. Save it on the Stripe page, then check again.');
    }
  }

  /// Shows [fresh] and, when it carries a card newer than [before], ends the
  /// setup. Returns whether it did.
  bool _cardLanded(Billing fresh, CardInfo? before) {
    _billing.setData(fresh);
    final card = fresh.card;
    if (card == null || !cardSaved(before, card)) return false;
    _endSetup();
    showRSnack(context, 'Card saved · ${cardLabel(card)}');
    return true;
  }

  void _endSetup() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _setup = _Setup.idle;
      _stripeUrl = null;
      _cardBefore = null;
      _autoStopped = false;
    });
  }

  void _openJob(String jobId) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => JobDetailScreen(jobId: jobId)));

  @override
  Widget build(BuildContext context) => PushedScreen(
    child: RLive<Billing>(
      controller: _billing,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
      builder: (context, billing) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Billing', style: RText.h1),
          const SizedBox(height: 18),
          if (billing.mode == PaymentMode.stripe) ...[
            ..._cardSection(billing),
            const SizedBox(height: 12),
          ] else if (billing.mode == PaymentMode.manual) ...[
            const _ManualCard(),
            const SizedBox(height: 12),
          ],
          _BalanceCard(billing.balanceDue),
          const SizedBox(height: 22),
          const RSectionLabel('Charges'),
          const SizedBox(height: 8),
          if (billing.charges.isEmpty)
            const REmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No charges yet',
              message: 'Each plough you request is listed here with its payment.',
            )
          else
            for (final charge in billing.charges)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ChargeCard(charge, onTap: () => _openJob(charge.jobId)),
              ),
        ],
      ),
    ),
  );

  List<Widget> _cardSection(Billing billing) {
    final card = billing.card;
    final expiry = card == null ? '' : cardExpiry(card);
    return [
      RCard(
        radius: 18,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: card == null ? RColors.paper2 : RColors.tealTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.credit_card_outlined,
                size: 20,
                color: card == null ? RColors.inkMuted : RColors.tealDeep,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card == null ? 'No card on file' : cardLabel(card), style: RText.title),
                  if (card == null)
                    Text('Add one to request ploughs.', style: RText.muted)
                  else if (expiry.isNotEmpty)
                    Text(expiry, style: RText.muted),
                ],
              ),
            ),
            if (card != null && _setup == _Setup.idle) ...[
              const SizedBox(width: 8),
              ROutlineButton('Replace card', busy: busy, onPressed: _startSetup),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        "A hold is placed on your card when you request a plough. You're charged only when "
        'the job is done, and the hold is released if the request is cancelled.',
        style: RText.muted.copyWith(height: 1.45),
      ),
      switch (_setup) {
        _Setup.idle => Column(
          children: [
            if (card == null) ...[
              const SizedBox(height: 14),
              RPrimaryButton(
                'Add card',
                icon: Icons.credit_card_outlined,
                busy: busy,
                onPressed: _startSetup,
              ),
            ],
            if (billing.pendingSetup) ...[
              const SizedBox(height: 12),
              RBanner(
                'A card setup was started but not finished.',
                actionLabel: 'Check now',
                onAction: _checkNow,
              ),
            ],
          ],
        ),
        _Setup.ready => _SetupPanel(
          title: 'Add your card on Stripe',
          message:
              "Stripe's secure page opens in a new tab. Your card number goes straight to "
              'Stripe; we only keep the card type, last four digits and expiry.',
          actions: [
            RPrimaryButton(
              'Continue to Stripe',
              icon: Icons.open_in_new_rounded,
              onPressed: _openStripe,
            ),
            _QuietButton('Cancel', onPressed: _endSetup),
          ],
        ),
        _Setup.waiting => _SetupPanel(
          title: 'Waiting for Stripe…',
          spinning: !_autoStopped,
          message: _autoStopped
              ? "We've stopped checking by ourselves. Once your card is saved on the Stripe "
                    'page, check again here.'
              : 'Save your card on the Stripe page. This screen updates by itself when it '
                    'is done.',
          actions: [
            RPrimaryButton("I've finished — check now", busy: busy, onPressed: _checkNow),
            const SizedBox(height: 8),
            ROutlineButton(
              'Open Stripe again',
              icon: Icons.open_in_new_rounded,
              fullWidth: true,
              onPressed: _openStripe,
            ),
            _QuietButton('Cancel', onPressed: _endSetup),
          ],
        ),
      },
    ];
  }
}

class _ManualCard extends StatelessWidget {
  const _ManualCard();

  @override
  Widget build(BuildContext context) => RCard(
    radius: 18,
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: RColors.tealTint, shape: BoxShape.circle),
          child: const Icon(Icons.receipt_long_outlined, size: 20, color: RColors.tealDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            "No card needed — you're billed after each job",
            style: RText.title.copyWith(height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard(this.balanceDue);
  final int balanceDue;

  @override
  Widget build(BuildContext context) => RCard(
    radius: 18,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Balance due', style: RText.title),
              const SizedBox(height: 2),
              Text(
                balanceDue > 0
                    ? 'For finished jobs that are not paid yet.'
                    : 'Nothing to pay right now.',
                style: RText.muted,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          money(balanceDue),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: balanceDue > 0 ? RColors.amber : RColors.teal,
            letterSpacing: -0.3,
          ),
        ),
      ],
    ),
  );
}

class _ChargeCard extends StatelessWidget {
  const _ChargeCard(this.charge, {required this.onTap});
  final Charge charge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = charge.date;
    final service = serviceLabel(shovel: charge.shovel);
    return RCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  charge.propertyName.isEmpty ? service : charge.propertyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RText.title,
                ),
                const SizedBox(height: 2),
                Text(date == null ? service : '${fmtDay(date)} · $service', style: RText.muted),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money(charge.total), style: RText.title),
              const SizedBox(height: 4),
              RPaymentPill.status(charge.status),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBBBBB)),
        ],
      ),
    );
  }
}

/// The bordered panel that walks the customer through saving a card.
class _SetupPanel extends StatelessWidget {
  const _SetupPanel({
    required this.title,
    required this.message,
    required this.actions,
    this.spinning = false,
  });
  final String title, message;
  final List<Widget> actions;
  final bool spinning;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: RCard(
      radius: 18,
      border: Border.all(color: RColors.teal, width: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (spinning) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(title, style: RText.title)),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: RText.muted.copyWith(height: 1.45)),
          const SizedBox(height: 14),
          ...actions,
        ],
      ),
    ),
  );
}

class _QuietButton extends StatelessWidget {
  const _QuietButton(this.label, {required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: RColors.inkMuted,
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    ),
  );
}
