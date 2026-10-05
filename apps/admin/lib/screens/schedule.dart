import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import 'post_card.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int _view = 1; // 0 Timeline, 1 Week, 2 Month
  late Future<List<JobCard>> _cards;

  @override
  void initState() {
    super.initState();
    _cards = api.jobCards();
  }

  void _reload() => setState(() => _cards = api.jobCards());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const RAppHeader(greeting: 'Hi Lia!', initials: adminInitials),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Schedule', style: RText.h1),
            Row(children: [
              _navArrow(Icons.chevron_left),
              const SizedBox(width: 6),
              _navArrow(Icons.chevron_right),
            ]),
          ]),
          const SizedBox(height: 4),
          Text('Next 4 weeks · 1 urgent · 3 to post', style: RText.muted),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: RSegmented(options: const ['Timeline', 'Week', 'Month'], index: _view, onChanged: (i) => setState(() => _view = i)),
          ),
          const SizedBox(height: 16),
          if (_view == 1) _weekView() else if (_view == 2) const _MonthView() else _timelineView(),
        ]),
      ),
    );
  }

  Widget _navArrow(IconData icon) => Container(
        width: 30, height: 30,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RColors.border, width: 0.6)),
        child: Icon(icon, size: 16, color: RColors.ink),
      );

  // ---- WEEK -------------------------------------------------------------
  Widget _weekView() {
    return FutureBuilder<List<JobCard>>(
      future: _cards,
      builder: (context, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal)));
        final cards = snap.data!;
        return Container(
          decoration: BoxDecoration(
            color: RColors.white,
            borderRadius: BorderRadius.circular(18),
            border: const Border(left: BorderSide(color: RColors.teal, width: 3), top: BorderSide(color: RColors.border, width: 0.6), right: BorderSide(color: RColors.border, width: 0.6), bottom: BorderSide(color: RColors.border, width: 0.6)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('This week · May 1 – 5', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink)),
              const SizedBox(width: 8),
              const RPill('NOW'),
            ]),
            const SizedBox(height: 6),
            Text('${cards.length} cards this week', style: RText.eyebrow),
            const SizedBox(height: 4),
            for (var i = 0; i < cards.length; i++) _weekRow(cards[i], i == 0),
          ]),
        );
      },
    );
  }

  Widget _weekRow(JobCard c, bool first) {
    final (bubbleBg, bubbleFg) = switch (c.status) {
      'urgent' => (RColors.amberTint, RColors.amber),
      'toPost' => (RColors.paper2, const Color(0xFF777777)),
      'awaiting' || 'claimed' => (RColors.tealTint, RColors.tealDeep),
      _ => (RColors.paper2, RColors.inkMuted),
    };
    final done = c.status == 'done';
    String meta;
    switch (c.status) {
      case 'urgent':
        meta = 'URGENT · FRIDAY · ${phaseLabel(c.phase).toUpperCase()}';
      case 'toPost':
        meta = '${phaseLabel(c.phase).toUpperCase()} · TO POST';
      case 'awaiting':
        meta = '${phaseLabel(c.phase)} · Awaiting crew';
      case 'claimed':
        meta = '${phaseLabel(c.phase)} · ${c.time}';
      default:
        meta = '${phaseLabel(c.phase)} · ${c.time}';
    }
    Widget trailing;
    switch (c.status) {
      case 'urgent':
        trailing = _miniButton('+ Self-assign', RColors.amber);
      case 'toPost':
        trailing = _miniButton('+ Post', const Color(0xFF999999), onTap: () async {
          await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PostCardScreen(propertyName: c.propertyName)));
          _reload();
        });
      case 'awaiting':
        trailing = Text('${c.slotsFilled}/${c.maxCrew}', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, color: RColors.inkMuted));
      case 'claimed':
        trailing = const RAvatar('MR', size: 22);
      default:
        trailing = const CircleAvatar(radius: 7, backgroundColor: RColors.teal, child: Icon(Icons.check, size: 9, color: Colors.white));
    }
    return Opacity(
      opacity: done ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6))),
        child: Row(children: [
          Container(width: 26, height: 26, decoration: BoxDecoration(color: bubbleBg, shape: BoxShape.circle), child: Icon(phaseIcon(c.phase), size: 14, color: bubbleFg)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.propertyName, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.ink, decoration: done ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 1),
            Text(meta, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, color: c.status == 'urgent' ? RColors.amber : (c.status == 'awaiting' ? RColors.tealDeep : RColors.inkMuted))),
          ])),
          trailing,
        ]),
      ),
    );
  }

  Widget _miniButton(String label, Color color, {VoidCallback? onTap}) => OutlinedButton(
        onPressed: onTap ?? () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: color, side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      );

  // ---- TIMELINE (compact per-card strip) --------------------------------
  Widget _timelineView() {
    return FutureBuilder<List<JobCard>>(
      future: _cards,
      builder: (context, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal)));
        final cards = snap.data!;
        return RCard(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < cards.length; i++) _timelineRow(cards[i], i > 0),
          ]),
        );
      },
    );
  }

  Widget _timelineRow(JobCard c, bool border) {
    final color = switch (c.status) {
      'urgent' => RColors.amber,
      'claimed' || 'done' => RColors.teal,
      'awaiting' => RColors.tealDeep,
      _ => const Color(0xFF999999),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
      child: Row(children: [
        const RAvatar('•', size: 24, colorKey: 'paper'),
        const SizedBox(width: 10),
        Expanded(child: Text(c.propertyName, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: RColors.ink))),
        RChip(phaseLabel(c.phase).split(' ').first, bg: color.withValues(alpha: 0.12), fg: color, icon: phaseIcon(c.phase), iconColor: color),
      ]),
    );
  }
}

// ---- MONTH calendar --------------------------------------------------------
class _MonthView extends StatelessWidget {
  const _MonthView();

  @override
  Widget build(BuildContext context) {
    // bar: 0 none, 1 full(teal), 2 gray, 3 urgent(amber); today flag for day 3.
    const weeks = [
      [(1, 1), (2, 1), (3, 3), (4, 2), (5, 2), (6, 0), (7, 0)],
      [(8, 2), (9, 0), (10, 2), (11, 0), (12, 2), (13, 0), (14, 0)],
      [(15, 2), (16, 0), (17, 2), (18, 0), (19, 0), (20, 0), (21, 0)],
      [(22, 0), (23, 2), (24, 0), (25, 0), (26, 0), (27, 0), (28, 0)],
      [(29, 0), (30, 0), (31, 0), (1, -1), (2, -1), (3, -1), (4, -1)],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final d in const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])
          Expanded(child: Center(child: Text(d, style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: RColors.inkSoft, letterSpacing: 0.5)))),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: RColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: RColors.border, width: 0.6)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var w = 0; w < weeks.length; w++)
            Container(
              decoration: BoxDecoration(border: w == 0 ? const Border(left: BorderSide(color: RColors.teal, width: 2)) : null),
              child: Row(children: [for (final cell in weeks[w]) Expanded(child: _cell(cell.$1, cell.$2, w == 0 && cell.$1 == 3))]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: RColors.tealTint, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.arrow_forward, size: 14, color: RColors.tealDeep),
          const SizedBox(width: 8),
          Expanded(child: Text('Wk of May 1 selected · tap any week row to open in Week view', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.tealDeep))),
        ]),
      ),
    ]);
  }

  Widget _cell(int day, int bar, bool today) {
    final off = bar == -1;
    return SizedBox(
      height: 46,
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const SizedBox(height: 8),
        if (today)
          CircleAvatar(radius: 12, backgroundColor: RColors.teal, child: Text('$day', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)))
        else
          Text('$day', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: off ? const Color(0xFFBBBBBB) : RColors.ink)),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: bar <= 0 ? const SizedBox(height: 5) : Container(width: 24, height: 5, decoration: BoxDecoration(
            color: bar == 1 ? RColors.teal : bar == 3 ? RColors.amber : RColors.inkSoft.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
          )),
        ),
      ]),
    );
  }
}
