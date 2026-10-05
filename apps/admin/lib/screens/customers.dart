import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import 'customer_detail.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late Future<({int total, int active, List<Customer> customers})> _data;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _data = api.customers();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<({int total, int active, List<Customer> customers})>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
          final d = snap.data!;
          final all = d.customers;
          final shown = _filter == 'all' ? all : all.where((c) => c.status == _filter).toList();
          final counts = {
            'all': all.length,
            'active': all.where((c) => c.status == 'active').length,
            'paused': all.where((c) => c.status == 'paused').length,
            'oneTime': all.where((c) => c.status == 'oneTime').length,
          };
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RAppHeader(greeting: 'Hi Lia!', initials: adminInitials),
              const SizedBox(height: 16),
              Text('Customers', style: RText.h1),
              const SizedBox(height: 4),
              Text('${d.total} customers · ${d.active} active subscriptions', style: RText.muted),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(color: RColors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: RColors.border, width: 0.6)),
                child: Row(children: [
                  const Icon(Icons.search, size: 16, color: Color(0xFF888888)),
                  const SizedBox(width: 10),
                  Text('Search by name or address', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkSoft)),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(height: 32, child: ListView(scrollDirection: Axis.horizontal, children: [
                _chip('All · ${counts['all']}', 'all'),
                _chip('Active · ${counts['active']}', 'active'),
                _chip('Paused · ${counts['paused']}', 'paused'),
                _chip('One-time · ${counts['oneTime']}', 'oneTime'),
              ])),
              const SizedBox(height: 14),
              RCard(radius: 18, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), child: Column(children: [
                for (var i = 0; i < shown.length; i++) _row(shown[i], i > 0),
              ])),
            ]),
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value) {
    final sel = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: sel ? RColors.tealTint : Colors.transparent, borderRadius: BorderRadius.circular(999), border: sel ? null : Border.all(color: RColors.border, width: 0.6)),
          child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w600, color: sel ? RColors.tealDeep : const Color(0xFF555555))),
        ),
      ),
    );
  }

  Widget _row(Customer c, bool border) => InkWell(
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id))),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
          child: Row(children: [
            RAvatar(c.initials, colorKey: c.color, size: 38),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink)),
              const SizedBox(height: 2),
              Text('${c.address} · ${c.secondary}', style: RText.muted),
            ])),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF888888)),
          ]),
        ),
      );
}
