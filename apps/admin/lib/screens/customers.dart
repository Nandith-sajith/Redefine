import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';
import 'customer_detail.dart';

final _spaces = RegExp(r'\s+');
final _nonDigits = RegExp(r'\D');
final _phoneLike = RegExp(r'^[\d()+.\-]+$');

/// Whether [customer] matches what the admin typed: every word must appear in
/// the name, email, phone or one of the addresses. A run of digits also
/// matches the phone number however it is punctuated.
bool matchesCustomer(Customer customer, String query) {
  final words = query.toLowerCase().split(_spaces).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final text = [
    customer.name,
    customer.email,
    customer.phone,
    ...customer.addresses,
  ].join('\n').toLowerCase();
  final phoneDigits = customer.phone.replaceAll(_nonDigits, '');
  return words.every((word) {
    if (text.contains(word)) return true;
    final digits = word.replaceAll(_nonDigits, '');
    return digits.length >= 3 && _phoneLike.hasMatch(word) && phoneDigits.contains(digits);
  });
}

/// `Oct 2`, or `today` / `yesterday` in lower case, to end a sentence with.
String dayInSentence(DateTime date) {
  final day = fmtDay(date);
  return day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : day;
}

enum _Filter { all, active, noCard }

typedef _CustomersData = ({List<Customer> customers, bool cards});

/// The Customers tab: everyone who signed up, searchable.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.active});

  /// Whether this tab is the one in front.
  final bool active;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  // The payments mode decides whether "No card" means anything.
  late final RLiveController<_CustomersData> _data = RLiveController(() async {
    final (customers, settings) = await both(api.customers(), api.settings());
    return (customers: customers, cards: settings.paymentsMode == PaymentMode.stripe);
  });
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _data.dispose();
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() => setState(() {
    _search.clear();
    _filter = _Filter.all;
  });

  @override
  Widget build(BuildContext context) => RLive<_CustomersData>(
    controller: _data,
    active: widget.active,
    pollEvery: const Duration(seconds: 60),
    padding: tabPadding,
    builder: (context, data) => _body(data.customers, cards: data.cards),
  );

  Widget _body(List<Customer> all, {required bool cards}) {
    final active = all.where((c) => c.activeProperties > 0).toList();
    final noCard = all.where((c) => !c.hasCard).toList();
    // The "No card" pill goes away with card payments.
    final filter = _filter == _Filter.noCard && !cards ? _Filter.all : _filter;
    final pool = switch (filter) {
      _Filter.all => all,
      _Filter.active => active,
      _Filter.noCard => noCard,
    };
    final shown = pool.where((c) => matchesCustomer(c, _search.text)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Customers', style: RText.h1),
        const SizedBox(height: 4),
        Text(
          '${countOf(all.length, 'customer')} · ${active.length} with an active property',
          style: RText.muted,
        ),
        const SizedBox(height: 14),
        _SearchField(
          controller: _search,
          onChanged: () => setState(() {}),
          onClear: () => setState(_search.clear),
        ),
        const SizedBox(height: 12),
        FilterRow(
          children: [
            FilterPill(
              label: 'All · ${all.length}',
              selected: filter == _Filter.all,
              onTap: () => setState(() => _filter = _Filter.all),
            ),
            FilterPill(
              label: 'Active · ${active.length}',
              selected: filter == _Filter.active,
              onTap: () => setState(() => _filter = _Filter.active),
            ),
            if (cards)
              FilterPill(
                label: 'No card · ${noCard.length}',
                selected: filter == _Filter.noCard,
                onTap: () => setState(() => _filter = _Filter.noCard),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          const REmptyState(
            icon: Icons.people_outline,
            title: 'No customers yet',
            message: 'Customers appear here when they sign up in the customer app.',
          )
        else if (shown.isEmpty)
          REmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            message: 'Nobody matches that search and filter.',
            action: ROutlineButton('Show everyone', onPressed: _clearSearch),
          )
        else
          ListCard(
            radius: 18,
            children: [for (final customer in shown) _row(customer, cards: cards)],
          ),
      ],
    );
  }

  Widget _row(Customer customer, {required bool cards}) {
    // When their newest job was requested, whatever became of it: it may
    // still be open, or have been cancelled.
    final last = customer.lastJobAt;
    return ListRow(
      onTap: () => pushScreen<void>(context, CustomerDetailScreen(customerId: customer.id)),
      child: PersonRow(
        initials: customer.initials,
        colorKey: customer.color,
        name: customer.name,
        subtitle:
            '${countOf(customer.propertyCount, 'property', 'properties')} · '
            '${last == null ? 'no requests yet' : 'last request ${dayInSentence(last)}'}',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cards && !customer.hasCard) ...[const RChip('NO CARD'), const SizedBox(width: 6)],
            rowChevron,
          ],
        ),
      ),
    );
  }
}

/// The pill-shaped search box, with a clear button once something is typed.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged, required this.onClear});
  final TextEditingController controller;
  final VoidCallback onChanged, onClear;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.ink);
    // A Material, so the clear button's ink shows on the white fill.
    return Material(
      color: RColors.white,
      shape: const StadiumBorder(side: BorderSide(color: RColors.border, width: 0.6)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: Color(0xFF888888)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                textInputAction: TextInputAction.search,
                cursorColor: RColors.teal,
                style: style,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  hintText: 'Search name, email, phone or address',
                  hintStyle: style.copyWith(color: RColors.inkSoft),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF888888)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              )
            else
              const SizedBox(width: 8, height: 30),
          ],
        ),
      ),
    );
  }
}
