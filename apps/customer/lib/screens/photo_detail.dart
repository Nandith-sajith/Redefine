import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

class PhotoDetailScreen extends StatelessWidget {
  const PhotoDetailScreen(this.visit, {super.key});
  final Visit visit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RBackRow('Back to timeline', onTap: () => Navigator.pop(context)),
            const SizedBox(height: 14),
            Text('${visit.date} visit', style: RText.h1),
            const SizedBox(height: 4),
            Text('${visit.weekday} · ${visit.ago}', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _photo('BEFORE', const Color(0xFF728E48), false)),
              const SizedBox(width: 8),
              Expanded(child: _photo('AFTER', const Color(0xFF5A8B45), true)),
            ]),
            const SizedBox(height: 16),
            RCard(
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                _row('Crew', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(color: RColors.tealTint, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(visit.crewInitials, style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: RColors.tealDeep)),
                  ),
                  const SizedBox(width: 6),
                  Text(visit.crew, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: RColors.ink)),
                ])),
                const Divider(height: 13, thickness: 0.6, color: RColors.borderSoft),
                _row('Duration', value: '${visit.durationMin} minutes'),
                const Divider(height: 13, thickness: 0.6, color: RColors.borderSoft),
                _row('Visit', value: '${visit.visitNumber} of ${visit.totalVisits}'),
              ]),
            ),
            const SizedBox(height: 18),
            const RSectionLabel('Crew note'),
            const SizedBox(height: 8),
            Text(visit.note, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic, color: const Color(0xFF555555), height: 1.55)),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, {String? value, Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: RColors.inkMuted)),
          trailing ?? Text(value ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: RColors.ink)),
        ]),
      );

  Widget _photo(String label, Color color, bool striped) => AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(children: [
            Positioned.fill(child: Container(color: color, child: striped ? CustomPaint(painter: _Stripes()) : null)),
            Positioned(
              top: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.6)),
              ),
            ),
          ]),
        ),
      );
}

class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF6BA055)..strokeWidth = 14;
    for (double x = -size.height; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
