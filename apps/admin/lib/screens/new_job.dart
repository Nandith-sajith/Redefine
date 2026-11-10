import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';
import 'customer_detail.dart' show cardName;
import 'customers.dart' show matchesCustomer;
import 'job_detail.dart';

/// Opens the new-job form and, once a job was created, that job's page.
Future<void> startNewJob(BuildContext context, {String? customerId, String? propertyId}) async {
  final job = await pushScreen<Job>(
    context,
    NewJobScreen(customerId: customerId, propertyId: propertyId),
  );
  if (job == null || !context.mounted) return;
  await pushScreen<void>(context, AdminJobDetailScreen(jobId: job.id, initial: job));
}

typedef _FormData = ({CustomerDetail detail, Settings settings});

/// Requests a plough on a customer's behalf (they phoned in, say): pick the
/// customer, one of their active properties, the service and how it is paid.
/// Pops with the created [Job].
class NewJobScreen extends StatefulWidget {
  const NewJobScreen({super.key, this.customerId, this.propertyId});

  /// Preselected when opened from a customer's page.
  final String? customerId, propertyId;

  @override
  State<NewJobScreen> createState() => _NewJobScreenState();
}

class _NewJobScreenState extends State<NewJobScreen> with BusyState<NewJobScreen> {
  late final RLiveController<List<Customer>> _customers = RLiveController(() => api.customers());
  final _search = TextEditingController();
  final _note = TextEditingController();

  /// The chosen customer and the form data loaded for them.
  String? _customerId;
  RLiveController<_FormData>? _form;

  String? _propertyId;
  bool _shovel = false;
  bool _billManually = false;

  /// A failed attempt that is explained in the form rather than in passing.
  ApiException? _problem;

  @override
  void initState() {
    super.initState();
    _propertyId = widget.propertyId;
    final customerId = widget.customerId;
    if (customerId != null) _choose(customerId);
  }

  @override
  void dispose() {
    _customers.dispose();
    _form?.dispose();
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  void _choose(String customerId) {
    _form?.dispose();
    _customerId = customerId;
    _form = RLiveController(() async {
      final (detail, settings) = await both(api.customer(customerId), api.settings());
      return (detail: detail, settings: settings);
    });
  }

  void _changeCustomer() => setState(() {
    _form?.dispose();
    _form = null;
    _customerId = null;
    _propertyId = null;
    _problem = null;
  });

  Future<void> _create(Property property, {required int total, CardInfo? holdOn}) async {
    if (busy) return;
    if (holdOn != null) {
      // Money moves on the customer's card, so ask first.
      final confirmed = await confirmDialog(
        context,
        title: 'Hold ${money(total)} on the card?',
        message:
            'A hold of ${money(total)} is placed on ${cardName(holdOn)} now. The customer is '
            'charged when the job is done, and the hold is released if the job is cancelled.',
        confirmLabel: 'Create job',
      );
      if (!confirmed || !mounted) return;
    }
    final card = holdOn != null;
    setState(() => _problem = null);
    final job = await run(
      () => api.requestJob(
        propertyId: property.id,
        shovel: _shovel,
        note: _note.text.trim(),
        payment: card ? 'card' : 'manual',
      ),
      success: 'Job created · open to all approved crew',
      onError: (e) {
        // The answer can outlive the form (the session ended meanwhile).
        if (!mounted) return true;
        // These need a decision here, so they stay on screen with a way out.
        if (e.code != 'job_active' && e.statusCode != 402) return false;
        setState(() => _problem = e);
        return true;
      },
    );
    if (job != null && mounted) Navigator.of(context).pop(job);
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    return PushedPage(
      // A job being created is handed back to whoever opened the form, so the
      // form stays up until the server has answered.
      canLeave: !busy,
      child: form == null
          ? RLive<List<Customer>>(
              key: const ValueKey('customers'),
              controller: _customers,
              padding: pagePadding,
              builder: (context, customers) => _pickCustomer(customers),
            )
          : RLive<_FormData>(
              key: ValueKey(_customerId),
              controller: form,
              padding: pagePadding,
              builder: (context, data) => _formBody(data.detail, data.settings),
            ),
    );
  }

  // ---- Step 1: the customer ----------------------------------------------

  Widget _pickCustomer(List<Customer> all) {
    final shown = all.where((c) => matchesCustomer(c, _search.text)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('New job', style: RText.h1),
        const SizedBox(height: 4),
        Text('Who is the plough for?', style: RText.muted),
        const SizedBox(height: 14),
        if (all.isEmpty)
          const REmptyState(
            icon: Icons.people_outline,
            title: 'No customers yet',
            message: 'A job needs a customer with an active property.',
          )
        else ...[
          RTextField(
            label: 'Customer',
            controller: _search,
            icon: Icons.search,
            hint: 'Search name, email, phone or address',
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const REmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message: 'Nobody matches that search.',
            )
          else
            ListCard(children: [for (final customer in shown) _customerRow(customer)]),
        ],
      ],
    );
  }

  Widget _customerRow(Customer customer) {
    final ready = customer.activeProperties > 0;
    final row = ListRow(
      onTap: ready ? () => setState(() => _choose(customer.id)) : null,
      child: PersonRow(
        initials: customer.initials,
        colorKey: customer.color,
        name: customer.name,
        subtitle: ready
            ? countOf(customer.activeProperties, 'active property', 'active properties')
            : 'No active property yet',
        trailing: ready ? rowChevron : null,
      ),
    );
    return ready ? row : Opacity(opacity: 0.5, child: row);
  }

  // ---- Step 2: the job ---------------------------------------------------

  Widget _formBody(CustomerDetail detail, Settings settings) {
    final customer = detail.customer;
    final active = detail.properties.where((p) => p.status == PropertyStatus.active).toList();
    final free = active.where((p) => p.activeJob == null).toList();
    final chosen = free.where((p) => p.id == _propertyId).toList();
    // With a single candidate there is nothing to choose.
    final property = chosen.isNotEmpty ? chosen.first : (free.length == 1 ? free.first : null);

    final card = detail.card;
    final canHold = settings.paymentsMode == PaymentMode.stripe && card != null;
    final useCard = canHold && !_billManually;

    final total = (property?.price ?? 0) + (_shovel ? settings.shovelPrice : 0);
    final crewPay = (property?.crewPay ?? 0) + (_shovel ? settings.crewShovelBonus : 0);

    final problem = _problem;
    final blockingJobId = problem?.extra['jobId'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('New job', style: RText.h1),
        const SizedBox(height: 14),
        const RSectionLabel('Customer'),
        const SizedBox(height: 8),
        RCard(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: PersonRow(
            initials: customer.initials,
            colorKey: customer.color,
            name: customer.name,
            subtitle: customer.phone.isNotEmpty ? customer.phone : customer.email,
            trailing: TextLink('Change', onTap: busy ? null : _changeCustomer),
          ),
        ),
        const SizedBox(height: 18),
        const RSectionLabel('Property'),
        const SizedBox(height: 8),
        if (active.isEmpty)
          const TextCard(
            'No active property. A property becomes active when the customer accepts its quote.',
          )
        else ...[
          for (final p in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _propertyOption(p, selected: p.id == property?.id),
            ),
          if (free.isEmpty)
            Text(
              'Every active property already has a job under way. A property takes one job '
              'at a time.',
              style: RText.muted.copyWith(height: 1.45),
            )
          else if (property == null)
            Text('Choose the property to plough.', style: RText.muted),
        ],
        if (property != null) ...[
          const SizedBox(height: 10),
          const RSectionLabel('Service'),
          const SizedBox(height: 8),
          RCard(
            radius: 14,
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add shovelling', style: RText.title.copyWith(fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        '${money(settings.shovelPrice)} more for the customer · '
                        '${money(settings.crewShovelBonus)} more for the crew',
                        style: RText.muted,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _shovel,
                  activeThumbColor: RColors.white,
                  activeTrackColor: RColors.teal,
                  onChanged: busy ? null : (value) => setState(() => _shovel = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RTextField(
            label: 'Note for the crew (optional)',
            controller: _note,
            hint: 'Gate code, where to pile the snow, what to watch for',
            maxLines: 3,
            maxLength: 500,
            enabled: !busy,
          ),
          const SizedBox(height: 18),
          const RSectionLabel('Payment'),
          const SizedBox(height: 8),
          if (canHold) ...[
            RSegmented(
              options: const ['Hold on card', 'Bill manually'],
              index: useCard ? 0 : 1,
              onChanged: busy
                  ? null
                  : (i) => setState(() {
                      _billManually = i == 1;
                      _problem = null;
                    }),
            ),
            const SizedBox(height: 8),
            Text(
              useCard
                  ? 'A hold is placed on ${cardName(card)} now and charged when the job '
                        'is done.'
                  : 'No card is touched. The job becomes due when it is done; mark it paid '
                        'from the job page.',
              style: RText.muted.copyWith(height: 1.45),
            ),
          ] else
            Text(
              settings.paymentsMode == PaymentMode.stripe
                  ? 'Billed manually: this customer has no card on file. The job becomes '
                        'due when it is done.'
                  : 'Billed manually: card payments are not set up. The job becomes due '
                        'when it is done.',
              style: RText.muted.copyWith(height: 1.45),
            ),
          const SizedBox(height: 18),
          _summary(total: total, crewPay: crewPay),
        ],
        if (problem != null) ...[
          const SizedBox(height: 14),
          if (problem.code == 'job_active')
            RBanner(
              problem.message,
              error: true,
              actionLabel: blockingJobId is String && blockingJobId.isNotEmpty ? 'Open job' : null,
              onAction: blockingJobId is String
                  ? () => pushScreen<void>(context, AdminJobDetailScreen(jobId: blockingJobId))
                  : null,
            )
          else
            RBanner(
              '${problem.message} You can bill this job manually instead.',
              error: true,
              actionLabel: 'Bill manually',
              onAction: () => setState(() {
                _billManually = true;
                _problem = null;
              }),
            ),
        ],
        if (property != null) ...[
          const SizedBox(height: 18),
          RPrimaryButton(
            'Create job',
            busy: busy,
            onPressed: () => _create(property, total: total, holdOn: useCard ? card : null),
          ),
        ],
      ],
    );
  }

  Widget _propertyOption(Property property, {required bool selected}) {
    final price = property.price, crewPay = property.crewPay;
    final job = property.activeJob;
    final taken = job != null;
    return RCard(
      radius: 14,
      padding: const EdgeInsets.all(14),
      border: selected
          ? Border.all(color: RColors.teal, width: 2)
          : Border.all(color: RColors.border, width: 0.6),
      onTap: taken || busy
          ? null
          : () => setState(() {
              _propertyId = property.id;
              _problem = null;
            }),
      child: Row(
        children: [
          Opacity(opacity: taken ? 0.5 : 1, child: PropertyIcon(property.illustration, size: 44)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RText.title.copyWith(
                    fontSize: 13,
                    color: taken ? RColors.inkMuted : RColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  property.address,
                  style: RText.muted.copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  taken
                      ? 'A job is already under way here'
                      : [
                          if (price != null) 'Customer pays ${money(price)}',
                          if (crewPay != null) 'crew earns ${money(crewPay)}',
                        ].join(' · '),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: taken ? RColors.inkMuted : RColors.tealDeep,
                  ),
                ),
              ],
            ),
          ),
          if (taken)
            TextLink(
              'Open job',
              onTap: busy
                  ? null
                  : () => pushScreen<void>(
                      context,
                      AdminJobDetailScreen(jobId: job.id, initial: job),
                    ),
            )
          else if (selected)
            const Icon(Icons.check_circle_rounded, size: 20, color: RColors.teal)
          else
            const Icon(Icons.radio_button_unchecked_rounded, size: 20, color: RColors.inkSoft),
        ],
      ),
    );
  }

  Widget _summary({required int total, required int crewPay}) => RCard(
    radius: 14,
    color: RColors.tealTint,
    border: Border.all(color: RColors.tealTint),
    child: Column(
      children: [
        KeyValueRow('Customer pays', money(total), strong: true),
        KeyValueRow('Crew earns', money(crewPay), strong: true),
        KeyValueRow('Service', serviceLabel(shovel: _shovel)),
      ],
    ),
  );
}
