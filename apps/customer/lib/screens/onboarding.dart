import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets.dart';

// ---------------------------------------------------------------------------
// Entry: a brand-new-property flow. EmptyState -> Picker -> Form -> Waiting ->
// QuoteReceived, all wired through the API.
// ---------------------------------------------------------------------------
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({super.key});
  @override
  Widget build(BuildContext context) => const _EmptyState();
}

Widget _scaffold(BuildContext context, {required List<Widget> children, Widget? bottom}) {
  return Scaffold(
    backgroundColor: RColors.surface,
    body: SafeArea(
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: RAppHeader(greeting: 'Hi Sarah!', initials: customerInitials),
        ),
        Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children))),
        if (bottom != null) Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: bottom),
      ]),
    ),
  );
}

// ---- Step 0: Empty state ---------------------------------------------------
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    void next() => Navigator.push(context, MaterialPageRoute(builder: (_) => const _PropertyPicker()));
    return _scaffold(context, children: [
      PropertyTabStrip(tabs: const [], onAdd: next),
      const Padding(
        padding: EdgeInsets.fromLTRB(22, 6, 22, 0),
        child: Row(children: [
          Icon(Icons.arrow_upward, size: 14, color: RColors.teal),
          SizedBox(width: 6),
          Text('Tap up here to get started', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.tealDeep)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
        child: Column(children: [
          Icon(Icons.add_home_outlined, size: 96, color: RColors.teal.withValues(alpha: 0.45)),
          const SizedBox(height: 16),
          Text('Add your first property', style: RText.h1, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Tap the + Add property tab above to set up your first lawn. We\'ll take it from there.',
              textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: RColors.inkMuted, height: 1.5)),
          const SizedBox(height: 22),
          RPrimaryButton('Add property', onPressed: next),
        ]),
      ),
    ]);
  }
}

// ---- Step 1: Pick an illustration -----------------------------------------
class _PropertyPicker extends StatefulWidget {
  const _PropertyPicker();
  @override
  State<_PropertyPicker> createState() => _PropertyPickerState();
}

class _PropertyPickerState extends State<_PropertyPicker> {
  int _sel = 1;
  static const _options = [
    (Icons.house_rounded, RColors.teal),
    (Icons.home_rounded, Color(0xFFA0432F)),
    (Icons.cabin, RColors.slate),
    (Icons.warehouse_rounded, Color(0xFF9C9C99)),
    (Icons.cottage_rounded, Color(0xFF7A4F2E)),
    (Icons.holiday_village_rounded, Color(0xFF8A4F3A)),
    (Icons.forest_rounded, Color(0xFF2A5C3A)),
    (Icons.house_siding_rounded, Color(0xFF882424)),
    (Icons.villa_rounded, Color(0xFF5A3A8A)),
  ];

  @override
  Widget build(BuildContext context) {
    return _scaffold(
      context,
      children: [
        PropertyTabStrip(tabs: const [PropertyTab(name: 'Setting up…', illo: 'house', selected: true)]),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('STEP 1 OF 3', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.inkMuted, letterSpacing: 0.6)),
            const SizedBox(height: 6),
            Text('Pick an illustration', style: RText.h1),
            const SizedBox(height: 6),
            Text('It helps you spot this property at a glance.', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: _options.length,
              itemBuilder: (_, i) {
                final sel = i == _sel;
                return GestureDetector(
                  onTap: () => setState(() => _sel = i),
                  child: Stack(children: [
                    Container(
                      decoration: BoxDecoration(
                        color: sel ? RColors.tealTint : RColors.paper2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? RColors.teal : RColors.border, width: sel ? 2 : 0.6),
                      ),
                      child: Center(child: Icon(_options[i].$1, size: 46, color: _options[i].$2)),
                    ),
                    if (sel)
                      Positioned(top: 6, right: 6, child: Container(
                        width: 20, height: 20,
                        decoration: const BoxDecoration(color: RColors.lime, shape: BoxShape.circle),
                        child: const Icon(Icons.check, size: 12, color: RColors.ink),
                      )),
                  ]),
                );
              },
            ),
          ]),
        ),
      ],
      bottom: RPrimaryButton('Continue', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _QuoteForm()))),
    );
  }
}

// ---- Step 2: Quote form ----------------------------------------------------
class _QuoteForm extends StatefulWidget {
  const _QuoteForm();
  @override
  State<_QuoteForm> createState() => _QuoteFormState();
}

class _QuoteFormState extends State<_QuoteForm> {
  int _service = 0;
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    Quote q;
    try {
      q = await api.createQuote({
        'customerId': customerId,
        'customerName': customerName,
        'customerInitials': customerInitials,
        'email': 'sarah.m@gmail.com',
        'phone': '(807) 555-0142',
        'propertyName': 'Maple Street home',
        'address': '412 Maple St',
        'serviceType': _service == 0 ? 'biweekly' : 'oneTime',
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the API. Is it running?')));
      return;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _Waiting(quoteId: q.id)));
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return _scaffold(
      context,
      children: [
        PropertyTabStrip(tabs: const [PropertyTab(name: 'Maple St', illo: 'house', selected: true)]),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tell us about your lawn', style: RText.h1),
            const SizedBox(height: 6),
            Text("We'll send a crew to take a look and get back to you within 2 business days.",
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted, height: 1.5)),
            const SizedBox(height: 18),
            Text('WHAT SERVICE?', style: RText.eyebrow),
            const SizedBox(height: 8),
            _radio('Lawn care (bi-weekly)', '16-visit seasonal program', 0),
            const SizedBox(height: 8),
            _radio('Lawn mowing only (one-time)', 'Single mow, no commitment', 1),
            const SizedBox(height: 16),
            _field('NAME', 'Sarah Mitchell'),
            _field('EMAIL', 'sarah.m@gmail.com'),
            _field('PHONE', '(807) 555-0142'),
            _field('PROPERTY', 'Maple Street home', sub: '412 Maple St, Thunder Bay, ON'),
            const SizedBox(height: 8),
            Text('NOTES FOR THE CREW', style: RText.eyebrow),
            const SizedBox(height: 6),
            Container(
              height: 70,
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF4F2EC), borderRadius: BorderRadius.circular(14), border: Border.all(color: RColors.border, width: 0.6)),
              child: Text('Gates, pets, tricky corners…', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontStyle: FontStyle.italic, color: const Color(0xFFBBBBBB))),
            ),
          ]),
        ),
      ],
      bottom: RPrimaryButton(_submitting ? 'Sending…' : 'Request estimate', onPressed: _submitting ? null : _submit),
    );
  }

  Widget _radio(String title, String sub, int i) {
    final sel = i == _service;
    return GestureDetector(
      onTap: () => setState(() => _service = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: RColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: sel ? RColors.teal : RColors.border, width: sel ? 2 : 0.6)),
        child: Row(children: [
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: sel ? RColors.teal : const Color(0xFFD5D2C9), width: 1.5)),
            child: sel ? const Center(child: CircleAvatar(radius: 4.5, backgroundColor: RColors.teal)) : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: RColors.ink)),
            const SizedBox(height: 2),
            Text(sub, style: RText.muted),
          ])),
        ]),
      ),
    );
  }

  Widget _field(String label, String value, {String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RColors.border, width: 0.6))),
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: RText.eyebrow),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w500, color: RColors.ink)),
            if (sub != null) Text(sub, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted)),
          ]),
        ),
      );
}

// ---- Step 3: Waiting -------------------------------------------------------
class _Waiting extends StatefulWidget {
  const _Waiting({required this.quoteId});
  final String quoteId;
  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Simulate the crew visiting and the admin pricing the quote.
    Future.delayed(const Duration(milliseconds: 1400), () async {
      try {
        await api.sendQuote(widget.quoteId, 52);
      } catch (_) {}
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _scaffold(
      context,
      children: [
        PropertyTabStrip(tabs: const [PropertyTab(name: 'Maple St', illo: 'house', selected: true)]),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const RChip('Estimate requested', icon: Icons.schedule, iconColor: Color(0xFF777777)),
            const SizedBox(height: 14),
            Text('Your quote is on the way', style: RText.h1),
            const SizedBox(height: 8),
            Text("A crew will swing by to take a look within 2 business days. We'll send you a notification the moment your quote is ready.",
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: RColors.inkMuted, height: 1.5)),
            const SizedBox(height: 24),
            RCard(radius: 18, padding: const EdgeInsets.all(18), child: Column(children: [
              _step(done: true, title: 'Request submitted', sub: 'Today, 9:38am'),
              _step(current: true, title: 'On-site visit & pricing', sub: 'Crew + admin meet you, discuss the plan'),
              _step(title: 'Quote ready', sub: 'Soon after', last: true),
            ])),
          ]),
        ),
      ],
      bottom: _ready
          ? RPrimaryButton('See your quote', icon: Icons.check_circle_outline, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _QuoteReceived(quoteId: widget.quoteId))))
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal)),
              const SizedBox(width: 10),
              Text('Crew is taking a look…', style: RText.muted),
            ]),
    );
  }

  Widget _step({bool done = false, bool current = false, required String title, required String sub, bool last = false}) {
    final circle = done
        ? const CircleAvatar(radius: 11, backgroundColor: RColors.teal, child: Icon(Icons.check, size: 11, color: Colors.white))
        : current
            ? Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: RColors.teal, width: 1.5)), child: const Center(child: CircleAvatar(radius: 4, backgroundColor: RColors.teal)))
            : Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFD5D2C9), width: 1.5)));
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [circle, if (!last) Container(width: 1.5, height: 26, color: done ? RColors.teal : RColors.border)]),
        const SizedBox(width: 14),
        Expanded(child: Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: (done || current) ? RColors.ink : const Color(0xFF777777))),
            const SizedBox(height: 2),
            Text(sub, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: (done || current) ? RColors.inkMuted : RColors.inkSoft)),
          ]),
        )),
      ]),
    );
  }
}

// ---- Step 4: Quote received -----------------------------------------------
class _QuoteReceived extends StatelessWidget {
  const _QuoteReceived({required this.quoteId});
  final String quoteId;

  Future<void> _accept(BuildContext context, String plan) async {
    try {
      await api.acceptQuote(quoteId, plan);
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan accepted — welcome aboard! 🌱')));
  }

  @override
  Widget build(BuildContext context) {
    return _scaffold(context, children: [
      PropertyTabStrip(tabs: const [
        PropertyTab(name: 'Maple St', illo: 'house', selected: true, badge: true),
        PropertyTab(name: 'Cabin', illo: 'cabin'),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const RPill('Quote ready', dot: RColors.teal),
          const SizedBox(height: 12),
          Text('Pick a plan to get started', style: RText.h1),
          const SizedBox(height: 6),
          Text('Our crew visited on Apr 28 and put together two options for your lawn.', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted, height: 1.5)),
          const SizedBox(height: 18),
          _planCard(context, recommended: true),
          const SizedBox(height: 12),
          _planCard(context, recommended: false),
        ]),
      ),
    ]);
  }

  Widget _planCard(BuildContext context, {required bool recommended}) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(color: RColors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: recommended ? RColors.teal : RColors.border, width: recommended ? 2 : 0.6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(recommended ? 'Lawn care (bi-weekly)' : 'Lawn mowing only (one-time)', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: RColors.ink)),
          const SizedBox(height: 2),
          Text(recommended ? 'Custom-priced for your property · 16 visits over the season' : 'Single mow, no commitment', style: RText.muted),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(recommended ? '\$52' : '\$85', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -0.5)),
            const SizedBox(width: 5),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(recommended ? '/ visit' : 'one time', style: RText.muted)),
          ]),
          if (recommended) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFF2F8F5), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                _infoRow('Billed bi-weekly', '\$52 every 2 weeks'),
                const SizedBox(height: 4),
                _infoRow('Program length', '16 visits · ~8 months'),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(width: 90, child: ROutlineButton('Decline', color: const Color(0xFFB7B4AB), onPressed: () {})),
            const SizedBox(width: 8),
            Expanded(child: recommended
                ? RPrimaryButton('Accept & pay', onPressed: () => _accept(context, 'biweekly'))
                : ROutlineButton('Accept & pay', fullWidth: true, onPressed: () => _accept(context, 'oneTime'))),
          ]),
        ]),
      ),
      if (recommended)
        Positioned(top: -11, left: 14, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: RColors.lime, borderRadius: BorderRadius.circular(999)),
          child: Text('RECOMMENDED', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: 0.6)),
        )),
    ]);
  }

  Widget _infoRow(String l, String r) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF555555))),
        Text(r, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.ink)),
      ]);
}
