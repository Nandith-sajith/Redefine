import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';
import '../widgets/price_fields.dart';
import 'customer_detail.dart';

typedef _QuoteData = ({Quote quote, Settings settings});

/// A quote request: who asked, for which property, and the form to price it.
/// Pops with `true` once a quote has been sent.
class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.quoteId});
  final String quoteId;

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> with BusyState<QuoteDetailScreen> {
  late final RLiveController<_QuoteData> _data = RLiveController(_load);
  final _price = TextEditingController();
  final _crewPay = TextEditingController();
  bool _prefilled = false;

  @override
  void dispose() {
    _data.dispose();
    _price.dispose();
    _crewPay.dispose();
    super.dispose();
  }

  Future<_QuoteData> _load() async {
    final (quote, settings) = await both(api.quote(widget.quoteId), api.settings());
    // Only the first load fills the form: a later refresh must not overwrite
    // what is being typed.
    if (mounted && !_prefilled) {
      _prefilled = true;
      _price.text = quote.price?.toString() ?? '';
      _crewPay.text = quote.crewPay?.toString() ?? '';
    }
    return (quote: quote, settings: settings);
  }

  Future<void> _send(Quote quote) async {
    final pricing = parsePricing(_price.text, _crewPay.text);
    if (pricing == null) return;
    final resend = quote.status == QuoteStatus.sent;
    // Re-sending the same offer would change nothing.
    if (resend && pricing.price == quote.price && pricing.crewPay == quote.crewPay) return;
    final customer = firstNameOf(quote.customerName);
    final sent = await run(
      () => api.sendQuote(quote.id, price: pricing.price, crewPay: pricing.crewPay),
      success: resend
          ? 'Quote updated'
          : (customer.isEmpty ? 'Quote sent' : 'Quote sent to $customer'),
      onError: (e) {
        // The customer answered in the meantime: show where the quote stands.
        if (e.code == 'quote_not_open') _data.refresh();
        return false;
      },
    );
    if (sent != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => PushedPage(
    child: RLive<_QuoteData>(
      controller: _data,
      padding: pagePadding,
      builder: (context, data) => _body(data.quote, data.settings),
    ),
  );

  Widget _body(Quote quote, Settings settings) {
    final open = quote.status == QuoteStatus.pending || quote.status == QuoteStatus.sent;
    final requested = quote.createdAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusPill(quote),
        const SizedBox(height: 12),
        Text(
          quote.customerName.isEmpty ? 'Quote request' : 'Quote for ${quote.customerName}',
          style: RText.h1,
        ),
        const SizedBox(height: 6),
        Text(
          [if (requested != null) 'Requested ${fmtAgo(requested)}', quote.propertyName].join(' · '),
          style: RText.muted,
        ),
        const SizedBox(height: 14),
        ListCard(
          children: [
            ListRow(
              child: PersonRow(
                initials: quote.customerInitials,
                colorKey: quote.customerColor,
                name: quote.customerName,
                subtitle: 'Customer',
              ),
            ),
            if (quote.email.isNotEmpty)
              ContactRow(icon: Icons.mail_outline, value: quote.email, what: 'Email'),
            if (quote.phone.isNotEmpty)
              ContactRow(icon: Icons.phone_outlined, value: quote.phone, what: 'Phone'),
          ],
        ),
        const SizedBox(height: 12),
        RCard(
          child: Row(
            children: [
              PropertyIcon(quote.illustration, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quote.propertyName, style: RText.title.copyWith(fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(quote.address, style: RText.muted.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (quote.note.isNotEmpty) ...[
          const SizedBox(height: 16),
          const RSectionLabel('Note from the customer'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: RCard(
              radius: 14,
              child: Text(
                quote.note,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: const Color(0xFF444444),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        RSectionLabel(open ? 'Your price' : 'Quoted price'),
        const SizedBox(height: 8),
        if (open) ..._form(quote, settings) else ..._outcome(quote),
      ],
    );
  }

  List<Widget> _form(Quote quote, Settings settings) {
    final pricing = parsePricing(_price.text, _crewPay.text);
    final resend = quote.status == QuoteStatus.sent;
    final unchanged =
        pricing != null && pricing.price == quote.price && pricing.crewPay == quote.crewPay;
    return [
      RCard(
        child: PriceFields(
          price: _price,
          crewPay: _crewPay,
          enabled: !busy,
          onChanged: () => setState(() {}),
          onSubmitted: () => _send(quote),
        ),
      ),
      const SizedBox(height: 12),
      RBanner(
        'Shovelling walkways and steps adds ${money(settings.shovelPrice)} for the customer '
        'and ${money(settings.crewShovelBonus)} for the crew. Change these in Settings.',
      ),
      if (resend) ...[
        const SizedBox(height: 12),
        Text(
          'This quote is with the customer. You can change the offer until they answer.',
          style: RText.muted.copyWith(height: 1.45),
        ),
      ],
      const SizedBox(height: 20),
      RPrimaryButton(
        resend ? 'Update quote' : 'Send quote',
        busy: busy,
        onPressed: pricing == null || (resend && unchanged) ? null : () => _send(quote),
      ),
    ];
  }

  List<Widget> _outcome(Quote quote) {
    final price = quote.price, crewPay = quote.crewPay, decided = quote.decidedAt;
    final (decision, next) = switch (quote.status) {
      QuoteStatus.accepted => (
        'Accepted',
        'The property is active. Change its price from the customer page; a new price '
            'applies to future requests.',
      ),
      QuoteStatus.declined => ('Declined', 'The customer can ask for a new quote from their app.'),
      _ => ('Decided', ''),
    };
    return [
      RCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (price != null) KeyValueRow('Customer pays per plough', money(price), strong: true),
            if (crewPay != null) KeyValueRow('Crew earns per plough', money(crewPay)),
            if (price != null && crewPay != null)
              KeyValueRow('Margin', money(price - crewPay), valueColor: RColors.tealDeep),
            if (decided != null) KeyValueRow(decision, fmtDayTime(decided)),
          ],
        ),
      ),
      if (next.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(next, style: RText.muted.copyWith(height: 1.45)),
      ],
      const SizedBox(height: 12),
      ROutlineButton(
        'View customer',
        fullWidth: true,
        icon: Icons.person_outline,
        onPressed: () =>
            pushScreen<void>(context, CustomerDetailScreen(customerId: quote.customerId)),
      ),
    ];
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.quote);
  final Quote quote;

  @override
  Widget build(BuildContext context) => switch (quote.status) {
    QuoteStatus.pending => const RPill(
      'NEEDS A PRICE',
      bg: RColors.amberTint,
      fg: Color(0xFF7A5514),
      dot: RColors.amber,
    ),
    QuoteStatus.sent => const RPill('SENT · WAITING FOR THE CUSTOMER', dot: RColors.teal),
    QuoteStatus.accepted => const RPill('ACCEPTED', icon: Icons.check_rounded),
    QuoteStatus.declined => const RPill('DECLINED', bg: RColors.dangerTint, fg: RColors.danger),
    QuoteStatus.unknown => const RPill('UNKNOWN', bg: RColors.paper2, fg: RColors.inkMuted),
  };
}
