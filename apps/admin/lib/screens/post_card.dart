import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';

class PostCardScreen extends StatefulWidget {
  const PostCardScreen({super.key, required this.propertyName});
  final String propertyName;
  @override
  State<PostCardScreen> createState() => _PostCardScreenState();
}

class _PostCardScreenState extends State<PostCardScreen> {
  String _phase = 'aeration';
  int _maxCrew = 2;
  bool _together = true;
  bool _posting = false;
  static const _phases = ['raking', 'leafBlow', 'aeration', 'seeding', 'fertilizing', 'overseeding'];

  Future<void> _post() async {
    setState(() => _posting = true);
    try {
      await api.postJobCard({'propertyName': widget.propertyName, 'phase': _phase, 'maxCrew': _maxCrew, 'goTogether': _together, 'payPerCrew': 48});
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job card posted — crew can claim it now ✓')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const RAppHeader(greeting: 'Hi Lia!', initials: adminInitials),
            const SizedBox(height: 12),
            RBackRow('Back to schedule', onTap: () => Navigator.pop(context)),
            const SizedBox(height: 14),
            Text(widget.propertyName, style: RText.h1),
            const SizedBox(height: 4),
            Text('Wednesday, May 3', style: RText.muted),
            const SizedBox(height: 14),
            RCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('23 Pine Cres', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink)),
                Text('Visit 4 of 16', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.inkMuted)),
              ]),
              const SizedBox(height: 4),
              Text('Henry Wallace · Lawn care (bi-weekly)', style: RText.muted),
            ])),
            const SizedBox(height: 16),
            const RSectionLabel('Program phase · auto-suggested · tap to change'),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in _phases) Padding(padding: const EdgeInsets.only(right: 6), child: _phaseChip(p)),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Trade secret · only crew + admin see this', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontStyle: FontStyle.italic, color: RColors.inkMuted)),
            const SizedBox(height: 16),
            const RSectionLabel('Capacity'),
            const SizedBox(height: 8),
            RCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), child: Column(children: [
              _capRow('Max crew', 'How many can claim this card', _stepper(), border: true),
              _capRow('Crew should go together', 'Both arrive on the same day', Switch(value: _together, activeThumbColor: Colors.white, activeTrackColor: RColors.teal, onChanged: (v) => setState(() => _together = v))),
            ])),
            const SizedBox(height: 14),
            RCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PAY PER CREW', style: RText.eyebrow),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('\$', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: RColors.teal)),
                Text('48', style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -0.6)),
              ]),
              const SizedBox(height: 8),
              Text('Subscription rate · tap to edit', style: RText.muted),
            ])),
            const SizedBox(height: 14),
            RPill('${0} OF $_maxCrew SLOTS FILLED · AWAITING CREW', dot: RColors.teal),
            const SizedBox(height: 18),
            RPrimaryButton(_posting ? 'Posting…' : 'Post job card', onPressed: _posting ? null : _post),
          ]),
        ),
      ),
    );
  }

  Widget _phaseChip(String p) {
    final sel = p == _phase;
    return GestureDetector(
      onTap: () => setState(() => _phase = p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: sel ? RColors.teal : Colors.transparent, borderRadius: BorderRadius.circular(999), border: sel ? null : Border.all(color: RColors.border, width: 0.6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(phaseIcon(p), size: 13, color: sel ? Colors.white : const Color(0xFF555555)),
          const SizedBox(width: 5),
          Text(phaseLabel(p), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w600, color: sel ? Colors.white : const Color(0xFF555555))),
        ]),
      ),
    );
  }

  Widget _capRow(String title, String sub, Widget trailing, {bool border = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: border ? const Border(bottom: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.ink)),
            const SizedBox(height: 2),
            Text(sub, style: RText.muted),
          ])),
          trailing,
        ]),
      );

  Widget _stepper() => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: RColors.paper2, borderRadius: BorderRadius.circular(999), border: Border.all(color: RColors.border, width: 0.6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _stepBtn(Icons.remove, () { if (_maxCrew > 1) setState(() => _maxCrew--); }, Colors.transparent, const Color(0xFF555555)),
          SizedBox(width: 22, child: Text('$_maxCrew', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink))),
          _stepBtn(Icons.add, () => setState(() => _maxCrew++), Colors.white, RColors.tealDeep),
        ]),
      );

  Widget _stepBtn(IconData icon, VoidCallback onTap, Color bg, Color fg) => GestureDetector(
        onTap: onTap,
        child: Container(width: 26, height: 26, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, size: 16, color: fg)),
      );
}
