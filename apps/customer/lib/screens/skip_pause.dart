import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

class SkipPauseScreen extends StatefulWidget {
  const SkipPauseScreen({super.key});
  @override
  State<SkipPauseScreen> createState() => _SkipPauseScreenState();
}

class _SkipPauseScreenState extends State<SkipPauseScreen> {
  bool _paused = false;
  final _skipped = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RBackRow('Back to Maple Street', onTap: () => Navigator.pop(context)),
            const SizedBox(height: 14),
            Text('Skip or pause', style: RText.h1),
            const SizedBox(height: 8),
            Text("Skip a single visit or pause your whole subscription. Just give us at least 48 hours notice.",
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted, height: 1.5)),
            const SizedBox(height: 18),
            RCard(
              radius: 18,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pause subscription', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: RColors.ink)),
                    const SizedBox(height: 4),
                    Text("All upcoming visits will be paused. Resume any time and we'll pick up where we left off.",
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: RColors.inkMuted, height: 1.45)),
                    const SizedBox(height: 6),
                    Text('Your bi-weekly billing pauses with the visits.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.tealDeep, height: 1.45)),
                  ]),
                ),
                const SizedBox(width: 14),
                Switch(
                  value: _paused,
                  activeThumbColor: Colors.white,
                  activeTrackColor: RColors.teal,
                  onChanged: (v) => setState(() => _paused = v),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            const RSectionLabel('Skip a visit'),
            const SizedBox(height: 8),
            RCard(
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                _skipRow('May 4', 'Tomorrow · in 16 hours', locked: true),
                _skipRow('May 6', 'Wednesday · in 3 days'),
                _skipRow('May 20', 'Wednesday · in 17 days'),
                _skipRow('Jun 3', 'Wednesday · in 31 days', last: true),
              ]),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: 'Need to cancel entirely? ', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: RColors.inkSoft)),
                TextSpan(text: 'Cancel subscription', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.tealDeep)),
              ])),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _skipRow(String date, String sub, {bool locked = false, bool last = false}) {
    final skipped = _skipped.contains(date);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: RColors.borderSoft, width: 0.6))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(date, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: RColors.ink)),
          const SizedBox(height: 2),
          Text(sub, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: locked ? RColors.inkSoft : RColors.inkMuted)),
        ]),
        if (locked)
          const RChip('Within 48 hrs', fg: Color(0xFF888888), icon: Icons.schedule, iconColor: Color(0xFF999999))
        else if (skipped)
          const RPill('Skipped', dot: RColors.teal)
        else
          ROutlineButton('Skip', onPressed: () => setState(() => _skipped.add(date))),
      ]),
    );
  }
}
