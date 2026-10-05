import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';

class JobDetailScreen extends StatelessWidget {
  const JobDetailScreen({super.key, required this.job});
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final phase = job['phase'] ?? 'aeration';
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const RAppHeader(greeting: 'Hi Marcus!', initials: crewInitials),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              RBackRow('Back to jobs', onTap: () => Navigator.pop(context)),
              Text('Today · ${job['time'] ?? ''}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.inkMuted)),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: Text(job['name'] ?? 'Job', style: RText.h1)),
              Text('\$${job['pay']}', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -0.4)),
            ]),
            const SizedBox(height: 4),
            Text('Sarah Mitchell · Visit 1 of 16', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted)),
            const SizedBox(height: 14),
            RPhaseTag(phase),
            const SizedBox(height: 14),
            RCard(
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.location_on_outlined, size: 18, color: RColors.teal),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(job['address'] ?? '412 Maple St', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: RColors.ink)),
                    const SizedBox(height: 2),
                    Text('Thunder Bay, ON · 8 min away', style: RText.muted),
                  ])),
                ]),
                const SizedBox(height: 12),
                ROutlineButton('Get directions', icon: Icons.navigation_outlined, fullWidth: true, onPressed: () {}),
              ]),
            ),
            const SizedBox(height: 14),
            const RSectionLabel('Notes from Sarah'),
            const SizedBox(height: 8),
            RCard(
              radius: 14,
              child: Text("Gate code is 1234. The dog is friendly but barks a lot — don't worry about her. Please watch the back garden bed near the fence, my daughter just planted bulbs there.",
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontStyle: FontStyle.italic, color: const Color(0xFF444444), height: 1.55)),
            ),
            const SizedBox(height: 20),
            RPrimaryButton('Start work', icon: Icons.play_arrow_rounded,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InProgressScreen(job: job)))),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class InProgressScreen extends StatefulWidget {
  const InProgressScreen({super.key, required this.job});
  final Map<String, dynamic> job;
  @override
  State<InProgressScreen> createState() => _InProgressScreenState();
}

class _InProgressScreenState extends State<InProgressScreen> {
  int _afterPhotos = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const RAppHeader(greeting: 'Hi Marcus!', initials: crewInitials),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              RBackRow('Back', onTap: () => Navigator.pop(context)),
              const RPill('In progress · 18 min', dot: RColors.teal),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: Text(widget.job['name'] ?? 'Maple Street home', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.5))),
              Text('\$${widget.job['pay']}', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -0.4)),
            ]),
            const SizedBox(height: 2),
            Text('${widget.job['address'] ?? '412 Maple St'} · Started 9:42am', style: RText.muted),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('BEFORE PHOTOS', style: RText.eyebrow),
              Row(children: [
                const CircleAvatar(radius: 6, backgroundColor: RColors.teal, child: Icon(Icons.check, size: 8, color: Colors.white)),
                const SizedBox(width: 5),
                Text('3 captured', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.tealDeep)),
              ]),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (final c in const [Color(0xFF728E48), Color(0xFF7A9050), Color(0xFF6F8E45)]) ...[
                Expanded(child: AspectRatio(aspectRatio: 1, child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12))))),
                if (c != const Color(0xFF6F8E45)) const SizedBox(width: 8),
              ],
            ]),
            const SizedBox(height: 18),
            Text('AFTER PHOTOS', style: RText.eyebrow),
            const SizedBox(height: 8),
            if (_afterPhotos == 0) _dropzone() else _afterGrid(),
            const SizedBox(height: 18),
            Opacity(
              opacity: _afterPhotos == 0 ? 0.5 : 1,
              child: RPrimaryButton('Mark complete',
                  color: _afterPhotos == 0 ? const Color(0xFFDDDDDD) : RColors.teal,
                  onPressed: _afterPhotos == 0 ? null : () async {
                    final id = widget.job['id']?.toString();
                    if (id != null && id.startsWith('job')) {
                      try { await api.completeJob(id); } catch (_) {}
                    }
                    if (!context.mounted) return;
                    Navigator.popUntil(context, (r) => r.isFirst);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job marked complete ✓')));
                  }),
            ),
            const SizedBox(height: 8),
            if (_afterPhotos == 0)
              Center(child: Text('Take at least one after photo to complete', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkSoft))),
          ]),
        ),
      ),
    );
  }

  Widget _dropzone() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
        decoration: BoxDecoration(color: const Color(0xFFF4F2EC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC5C2B9), width: 1.5)),
        child: Column(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: RColors.border, width: 0.6)), child: const Icon(Icons.photo_camera_outlined, size: 26, color: RColors.teal)),
          const SizedBox(height: 14),
          Text('Take after photos', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: RColors.ink)),
          const SizedBox(height: 6),
          Text('Capture each section — front, back, sides', style: RText.muted),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() => _afterPhotos = 3),
            style: ElevatedButton.styleFrom(backgroundColor: RColors.teal, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10)),
            child: const Text('Open camera'),
          ),
        ]),
      );

  Widget _afterGrid() => Row(children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(child: AspectRatio(aspectRatio: 1, child: Container(decoration: BoxDecoration(color: const Color(0xFF5A8B45), borderRadius: BorderRadius.circular(12))))),
          if (i < 2) const SizedBox(width: 8),
        ],
      ]);
}
