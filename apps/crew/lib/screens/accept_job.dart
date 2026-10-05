import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';

class AcceptJobScreen extends StatefulWidget {
  const AcceptJobScreen({super.key, required this.job});
  final JobCard job;
  @override
  State<AcceptJobScreen> createState() => _AcceptJobScreenState();
}

class _AcceptJobScreenState extends State<AcceptJobScreen> {
  int _day = 2;
  int _window = 1;
  bool _saving = false;

  static const _days = [('MON', '5', true), ('TUE', '6', false), ('WED', '7', false), ('THU', '8', false), ('FRI', '9', false)];
  static const _windows = ['Morning', 'Midday', 'Afternoon', 'Evening'];

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await api.claimJob(widget.job.id, crewId, '${_days[_day].$1} ${_days[_day].$2}', _windows[_window]);
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job claimed — it\'s in your Jobs tab 🎉')));
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const RAppHeader(greeting: 'Hi Marcus!', initials: crewInitials),
            const SizedBox(height: 14),
            RBackRow('Back to pending', onTap: () => Navigator.pop(context, false)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: Text(j.propertyName, style: RText.h1)),
              Text('\$${j.payPerCrew}', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -0.4)),
            ]),
            const SizedBox(height: 8),
            Row(children: [RPhaseTag(j.phase), const SizedBox(width: 8), Flexible(child: Text(j.address, style: RText.muted))]),
            const SizedBox(height: 16),
            Text('PICK A DAY THIS WEEK', style: RText.eyebrow),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < _days.length; i++) ...[
                Expanded(child: _dayChip(i)),
                if (i < _days.length - 1) const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 16),
            Text('PICK A TIME WINDOW', style: RText.eyebrow),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < _windows.length; i++) ...[
                Expanded(child: _windowChip(i)),
                if (i < _windows.length - 1) const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFF2F8F5), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.schedule, size: 16, color: RColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text(j.goTogether ? 'Goes together with 1 other crew. 1 slot stays open after you claim.' : 'Solo job — all yours once you claim.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.tealDeep, height: 1.45))),
              ]),
            ),
            const SizedBox(height: 18),
            RPrimaryButton(_saving ? 'Confirming…' : 'Confirm · take this job', onPressed: _saving ? null : _confirm),
          ]),
        ),
      ),
    );
  }

  Widget _dayChip(int i) {
    final (label, num, past) = _days[i];
    final sel = i == _day;
    return GestureDetector(
      onTap: past ? null : () => setState(() => _day = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? RColors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: sel ? null : Border.all(color: RColors.border, width: 0.6),
        ),
        child: Column(children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: sel ? Colors.white : (past ? RColors.inkSoft : const Color(0xFF777777)))),
          const SizedBox(height: 2),
          Text(num, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: sel ? Colors.white : (past ? RColors.inkSoft : RColors.ink))),
        ]),
      ),
    );
  }

  Widget _windowChip(int i) {
    final sel = i == _window;
    return GestureDetector(
      onTap: () => setState(() => _window = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? RColors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: sel ? null : Border.all(color: RColors.border, width: 0.6),
        ),
        child: Text(_windows[i], style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w600, color: sel ? Colors.white : RColors.ink)),
      ),
    );
  }
}
