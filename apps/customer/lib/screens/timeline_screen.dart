import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets.dart';
import 'onboarding.dart';
import 'photo_detail.dart';
import 'skip_pause.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late Future<List<Visit>> _visits;

  @override
  void initState() {
    super.initState();
    _visits = api.visits(propertyId: propertyId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: RAppHeader(greeting: 'Hi Sarah!', initials: customerInitials),
            ),
            PropertyTabStrip(
              tabs: const [
                PropertyTab(name: 'Maple St', illo: 'house', selected: true),
                PropertyTab(name: 'Cabin', illo: 'cabin'),
              ],
              onAdd: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingFlow())),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('412 Maple St · Visit 4 of 16 · Lawn care (bi-weekly)', style: RText.muted),
                const SizedBox(height: 16),
                const RSectionLabel('Up next'),
                const SizedBox(height: 8),
                _nextVisitCard(),
                const SizedBox(height: 10),
                _secondVisitCard(),
                const SizedBox(height: 20),
                const RSectionLabel('Completed'),
                const SizedBox(height: 4),
                _completedList(),
                const SizedBox(height: 6),
                _links(),
                const SizedBox(height: 18),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _nextVisitCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: RColors.tealDeep, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Wednesday', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(width: 8),
          Text('· in 3 days', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
        ]),
        const SizedBox(height: 6),
        Text('May 6', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.22)))),
          child: Row(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('MJ', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Text('Marcus & Jordan, 8–10am window', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.92))),
          ]),
        ),
      ]),
    );
  }

  Widget _secondVisitCard() {
    return RCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Wednesday · in 17 days', style: RText.muted),
          const SizedBox(height: 2),
          Text('May 20', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.3)),
        ]),
        const RChip('Crew TBD', fg: Color(0xFF888888)),
      ]),
    );
  }

  Widget _completedList() {
    return FutureBuilder<List<Visit>>(
      future: _visits,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal)));
        }
        final visits = snap.data!;
        return Column(children: [
          for (var i = 0; i < visits.length; i++) _visitRow(visits[i], i > 0),
        ]);
      },
    );
  }

  Widget _visitRow(Visit v, bool border) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoDetailScreen(v))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF5C8E45)),
            child: CustomPaint(painter: _StripePainter()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.date, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: RColors.ink)),
              const SizedBox(height: 2),
              Text('${v.crew} · ${v.durationMin} min', style: RText.muted),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBBBBB)),
        ]),
      ),
    );
  }

  Widget _links() {
    final items = [
      ('All photos', () {}),
      ('Billing & receipts', () {}),
      ('Skip or pause visits', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SkipPauseScreen()))),
    ];
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: RColors.borderSoft, width: 0.6))),
      child: Column(children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: items[i].$2,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: i > 0 ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(items[i].$1, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: RColors.ink)),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBBBBB)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Diagonal mowing-stripe texture for the photo thumbnails.
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF6FA055)..strokeWidth = 6;
    for (double x = -size.height; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
