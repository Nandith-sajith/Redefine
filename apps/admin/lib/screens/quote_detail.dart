import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';

class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.quoteId});
  final String quoteId;
  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  late Future<Quote> _quote;
  int _biweekly = 52;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _quote = api.quote(widget.quoteId);
  }

  Future<void> _editPrice() async {
    final ctrl = TextEditingController(text: '$_biweekly');
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bi-weekly rate'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '\$ ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, int.tryParse(ctrl.text)), child: const Text('Save')),
        ],
      ),
    );
    if (result != null) setState(() => _biweekly = result);
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await api.sendQuote(widget.quoteId, _biweekly);
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quote sent to the customer ✓')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: FutureBuilder<Quote>(
          future: _quote,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
            final q = snap.data!;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const RAppHeader(greeting: 'Hi Lia!', initials: adminInitials),
                const SizedBox(height: 12),
                RBackRow('Back to inbox', onTap: () => Navigator.pop(context)),
                const SizedBox(height: 14),
                RPill('PENDING ${q.pendingDays} DAYS', bg: RColors.amberTint, fg: RColors.amber, dot: RColors.amber),
                const SizedBox(height: 12),
                Text('Quote for ${q.customerName}', style: RText.h1),
                const SizedBox(height: 6),
                Text('Submitted ${q.submittedAt} · ${q.propertyName}', style: RText.muted),
                const SizedBox(height: 14),
                RCard(child: Row(children: [
                  RAvatar(q.customerInitials, size: 38),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(q.customerName, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: RColors.ink)),
                    const SizedBox(height: 1),
                    Text('${q.email} · ${q.phone}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkMuted)),
                  ])),
                ])),
                const SizedBox(height: 12),
                RCard(child: Row(children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(color: RColors.paper2, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.house_rounded, size: 30, color: RColors.teal)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(q.propertyName, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: RColors.ink)),
                    const SizedBox(height: 2),
                    Text(q.address, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkMuted)),
                    if (q.propertyDesc.isNotEmpty) ...[const SizedBox(height: 2), Text(q.propertyDesc, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: RColors.inkMuted))],
                  ])),
                ])),
                if (q.note.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  RSectionLabel('Note from ${q.customerName.split(' ').first}'),
                  const SizedBox(height: 8),
                  RCard(radius: 14, child: Text('"${q.note}"', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontStyle: FontStyle.italic, color: const Color(0xFF444444), height: 1.5))),
                ],
                if (q.crewVisit != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: RColors.tealTint, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const CircleAvatar(radius: 11, backgroundColor: RColors.lime, child: Icon(Icons.check, size: 12, color: RColors.tealDeep)),
                      const SizedBox(width: 10),
                      Text(q.crewVisit!, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.tealDeep)),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                const RSectionLabel('Pricing · base + location adjustment'),
                const SizedBox(height: 8),
                _recommendedCard(),
                const SizedBox(height: 12),
                _oneTimeCard(q.oneTimePrice ?? 85),
                const SizedBox(height: 22),
                RPrimaryButton(_sending ? 'Sending…' : 'Send quote to ${q.customerName.split(' ').first}', onPressed: _sending ? null : _send),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _recommendedCard() => Stack(clipBehavior: Clip.none, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: RColors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: RColors.teal, width: 2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Lawn care (bi-weekly)', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink)),
              GestureDetector(onTap: _editPrice, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('\$', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.teal)),
                Text('$_biweekly', style: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -0.5)),
                const SizedBox(width: 4),
                Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('/visit', style: RText.muted)),
                const SizedBox(width: 6),
                const Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.edit_outlined, size: 13, color: RColors.teal)),
              ])),
            ]),
            const SizedBox(height: 6),
            Text('Billed bi-weekly · 16 visits · ~8 months · tap to edit', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkMuted)),
          ]),
        ),
        Positioned(top: -9, left: 16, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: RColors.lime, borderRadius: BorderRadius.circular(999)),
          child: Text('RECOMMENDED', style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: 0.6)),
        )),
      ]);

  Widget _oneTimeCard(int price) => RCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Lawn mowing only (one-time)', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink)),
            Text('$price', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.5)),
          ]),
        ]),
        const SizedBox(height: 6),
        Text('Fixed price · single visit', style: RText.muted),
      ]));
}
