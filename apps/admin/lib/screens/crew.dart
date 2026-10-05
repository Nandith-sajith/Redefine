import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';

class CrewScreen extends StatefulWidget {
  const CrewScreen({super.key});
  @override
  State<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends State<CrewScreen> {
  late Future<({List<CrewMember> active, List<CrewMember> pending})> _crew;

  @override
  void initState() {
    super.initState();
    _crew = api.crew();
  }

  void _reload() => setState(() => _crew = api.crew());

  Future<void> _decide(CrewMember c, bool approve) async {
    try {
      approve ? await api.approveCrew(c.id) : await api.rejectCrew(c.id);
    } catch (_) {}
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? '${c.name} approved 🎉' : '${c.name} rejected')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<({List<CrewMember> active, List<CrewMember> pending})>(
        future: _crew,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
          final active = snap.data!.active, pending = snap.data!.pending;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RAppHeader(greeting: 'Hi Lia!', initials: adminInitials),
              const SizedBox(height: 16),
              Text('Crew', style: RText.h1),
              const SizedBox(height: 4),
              Text('${active.length} active · ${pending.length} pending approval', style: RText.muted),
              const SizedBox(height: 18),
              if (pending.isNotEmpty) ...[
                const RSectionLabel('Pending approval'),
                const SizedBox(height: 14),
                for (final c in pending) _pendingCard(c),
                const SizedBox(height: 18),
              ],
              const RSectionLabel('Active crew'),
              const SizedBox(height: 8),
              RCard(radius: 14, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), child: Column(children: [
                for (var i = 0; i < active.length; i++) _activeRow(active[i], i > 0),
              ])),
              const SizedBox(height: 14),
              Center(child: Text('+ Invite a crew member', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.tealDeep))),
            ]),
          );
        },
      ),
    );
  }

  Widget _pendingCard(CrewMember c) => Stack(clipBehavior: Clip.none, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: RColors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: RColors.lime, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              RAvatar(c.initials, colorKey: 'teal', size: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.ink)),
                const SizedBox(height: 2),
                Text(c.appliedAgo, style: RText.muted),
              ])),
            ]),
            const SizedBox(height: 12),
            RCard(radius: 12, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2), child: Column(children: [
              _infoRow(Icons.mail_outline, c.email, true),
              _infoRow(Icons.phone_outlined, c.phone, true),
              _infoRow(Icons.school_outlined, c.experience, false),
            ])),
            const SizedBox(height: 14),
            Row(children: [
              ROutlineButton('Reject', color: const Color(0xFF888888), onPressed: () => _decide(c, false)),
              const SizedBox(width: 8),
              Expanded(child: RPrimaryButton('Approve', onPressed: () => _decide(c, true))),
            ]),
          ]),
        ),
        Positioned(top: -9, left: 16, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: RColors.lime, borderRadius: BorderRadius.circular(999)),
          child: Text('NEW APPLICATION', style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: 0.6)),
        )),
      ]);

  Widget _infoRow(IconData icon, String text, bool border) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: border ? const Border(bottom: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Row(children: [
          Icon(icon, size: 14, color: const Color(0xFF777777)),
          const SizedBox(width: 10),
          Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: RColors.ink)),
        ]),
      );

  Widget _activeRow(CrewMember c, bool border) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Row(children: [
          RAvatar(c.initials, colorKey: c.color, size: 38),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: RColors.ink)),
            const SizedBox(height: 2),
            Text('${c.jobsThisWeek} jobs this week · \$${c.payThisWeek}', style: RText.muted),
          ])),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFF888888)),
        ]),
      );
}
