import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';
import '../widgets/job_widgets.dart';
import '../widgets/price_fields.dart';
import 'customers.dart' show dayInSentence;
import 'job_detail.dart';
import 'new_job.dart';
import 'quote_detail.dart';

/// How many recent jobs are listed before "Show all".
const _recentJobs = 5;

/// `Visa ending 4242`: how a saved card is named inside a sentence.
String cardName(CardInfo card) {
  final brand = card.brand.isEmpty
      ? 'Card'
      : '${card.brand[0].toUpperCase()}${card.brand.substring(1)}';
  return card.last4.isEmpty ? brand : '$brand ending ${card.last4}';
}

/// `Visa ending 4242 · expires 08/27`.
String cardLabel(CardInfo card) {
  final name = cardName(card);
  if (card.expMonth < 1 || card.expMonth > 12) return name;
  final month = card.expMonth.toString().padLeft(2, '0');
  final year = (card.expYear % 100).toString().padLeft(2, '0');
  return '$name · expires $month/$year';
}

/// One customer: contact details, what they were billed, their properties
/// with the price of each, and their recent jobs.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with BusyState<CustomerDetailScreen> {
  late final RLiveController<CustomerDetail> _detail = RLiveController(
    () => api.customer(widget.customerId),
  );

  /// The property whose new price is being saved.
  String? _repricing;
  bool _showAllJobs = false;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _editPrice(Property property) async {
    final pricing = await showEditPriceDialog(
      context,
      title: 'Price for ${property.name}',
      initialPrice: property.price,
      initialCrewPay: property.crewPay,
      note: 'The new price applies to future requests. Jobs already requested keep theirs.',
    );
    if (pricing == null || !mounted || busy) return;
    if (pricing.price == property.price && pricing.crewPay == property.crewPay) return;
    setState(() => _repricing = property.id);
    await run(
      () => api.setPropertyPrice(property.id, price: pricing.price, crewPay: pricing.crewPay),
      success: 'Price updated · ${money(pricing.price)} per plough',
    );
    if (!mounted) return;
    setState(() => _repricing = null);
    // Also after a failure: the property may no longer be active.
    _detail.refresh(silent: true);
  }

  void _openJob(Job job) =>
      pushScreen<void>(context, AdminJobDetailScreen(jobId: job.id, initial: job));

  @override
  Widget build(BuildContext context) => PushedPage(
    child: RLive<CustomerDetail>(
      controller: _detail,
      pollEvery: const Duration(seconds: 30),
      padding: pagePadding,
      builder: (context, detail) => _body(detail),
    ),
  );

  Widget _body(CustomerDetail detail) {
    final customer = detail.customer;
    final card = detail.card;
    final since = customer.createdAt;
    final jobs = _showAllJobs ? detail.jobs : detail.jobs.take(_recentJobs).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RAvatar(
              customer.initials,
              colorKey: customer.color.isEmpty ? 'lime' : customer.color,
              size: 56,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: RColors.ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        card == null ? Icons.credit_card_off_outlined : Icons.credit_card_rounded,
                        size: 14,
                        color: card == null ? RColors.inkSoft : RColors.tealDeep,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          card == null ? 'No card on file' : cardLabel(card),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: card == null ? RColors.inkMuted : RColors.tealDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (since != null) ...[
                    const SizedBox(height: 2),
                    Text('Customer since ${dayInSentence(since)}', style: RText.muted),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Billed',
                value: money(detail.billed),
                valueColor: RColors.tealDeep,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Outstanding',
                value: money(detail.outstanding),
                valueColor: detail.outstanding > 0 ? amberInk : RColors.ink,
              ),
            ),
          ],
        ),
        if (customer.email.isNotEmpty || customer.phone.isNotEmpty) ...[
          const SizedBox(height: 12),
          ContactCard(email: customer.email, phone: customer.phone),
        ],
        const SizedBox(height: 18),
        RSectionLabel('Properties · ${detail.properties.length}'),
        const SizedBox(height: 8),
        if (detail.properties.isEmpty)
          const TextCard('No properties yet. They add one in the customer app to ask for a quote.')
        else
          for (final property in detail.properties)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: _propertyCard(property)),
        const SizedBox(height: 10),
        RSectionLabel(
          _showAllJobs || detail.jobs.length <= _recentJobs ? 'Jobs' : 'Recent jobs',
          trailing: detail.jobs.length > _recentJobs
              ? TextLink(
                  _showAllJobs ? 'Show fewer' : 'Show all ${detail.jobs.length}',
                  onTap: () => setState(() => _showAllJobs = !_showAllJobs),
                )
              : null,
        ),
        const SizedBox(height: 8),
        if (jobs.isEmpty)
          const TextCard('No ploughs yet.')
        else
          ListCard(
            radius: 14,
            children: [for (final job in jobs) JobRow(job, onTap: () => _openJob(job))],
          ),
      ],
    );
  }

  Widget _propertyCard(Property property) {
    final price = property.price, crewPay = property.crewPay;
    final job = property.activeJob;
    final (line, lineColor) = switch (property.status) {
      PropertyStatus.active => (
        price == null
            ? 'Active'
            : 'Customer pays ${money(price)}'
                  '${crewPay == null ? '' : ' · crew earns ${money(crewPay)}'}',
        RColors.tealDeep,
      ),
      PropertyStatus.quoteRequested => ('Waiting for your price', amberInk),
      PropertyStatus.quoted => (
        price == null
            ? 'Quote sent · waiting for the customer'
            : 'Quoted ${money(price)} per plough · waiting for the customer',
        RColors.inkMuted,
      ),
      PropertyStatus.declined => ('Quote declined', RColors.inkMuted),
      PropertyStatus.unknown => ('', RColors.inkMuted),
    };
    final hasQuote =
        property.quoteId.isNotEmpty &&
        (property.status == PropertyStatus.quoteRequested ||
            property.status == PropertyStatus.quoted);
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PropertyIcon(property.illustration),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.name,
                      style: RText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(property.address, style: RText.muted),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        line,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: lineColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (property.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              property.note,
              style: RText.muted.copyWith(fontStyle: FontStyle.italic, height: 1.4),
            ),
          ],
          if (property.status == PropertyStatus.active) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ROutlineButton(
                    'Edit price',
                    fullWidth: true,
                    busy: _repricing == property.id,
                    onPressed: busy ? null : () => _editPrice(property),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // One unfinished job per property: link to it instead.
                  child: job == null
                      ? ROutlineButton(
                          'New job',
                          fullWidth: true,
                          icon: Icons.add_rounded,
                          color: RColors.tealDeep,
                          onPressed: () => startNewJob(
                            context,
                            customerId: widget.customerId,
                            propertyId: property.id,
                          ),
                        )
                      : ROutlineButton(
                          'Open live job',
                          fullWidth: true,
                          color: RColors.tealDeep,
                          onPressed: () => _openJob(job),
                        ),
                ),
              ],
            ),
          ],
          if (hasQuote) ...[
            const SizedBox(height: 12),
            ROutlineButton(
              'Open quote',
              fullWidth: true,
              color: RColors.tealDeep,
              onPressed: () =>
                  pushScreen<bool>(context, QuoteDetailScreen(quoteId: property.quoteId)),
            ),
          ],
        ],
      ),
    );
  }
}
