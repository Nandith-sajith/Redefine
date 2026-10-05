import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<Map<String, dynamic>> _data;
  Future<List<Visit>>? _visits;

  @override
  void initState() {
    super.initState();
    _data = api.customer(widget.customerId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
            final c = snap.data!;
            final props = ((c['properties'] as List?) ?? const []).cast<Map<String, dynamic>>();
            final active = c['status'] == 'active';
            _visits ??= active && props.isNotEmpty ? api.visits(propertyId: props.first['id']) : Future.value(<Visit>[]);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const RAppHeader(greeting: 'Hi Lia!', initials: adminInitials),
                const SizedBox(height: 12),
                RBackRow('Back to customers', onTap: () => Navigator.pop(context)),
                const SizedBox(height: 14),
                Row(children: [
                  RAvatar(c['initials'] ?? '', colorKey: c['color'] ?? 'lime', size: 56),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['name'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.4)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: active ? RColors.teal : RColors.inkSoft, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(_serviceLine(c), style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: active ? RColors.tealDeep : RColors.inkMuted))),
                      Text(' · ${c['since']}', style: RText.muted),
                    ]),
                  ])),
                ]),
                if (active) ...[
                  const SizedBox(height: 18),
                  RSectionLabel('Program · 16 visits', trailing: Text('Visit 5 of 16', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, color: RColors.inkMuted))),
                  const SizedBox(height: 8),
                  _programTrack(),
                ],
                const SizedBox(height: 18),
                RCard(radius: 14, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), child: Column(children: [
                  _contactRow(Icons.mail_outline, c['email'] ?? '', true),
                  _contactRow(Icons.phone_outlined, c['phone'] ?? '', false),
                ])),
                const SizedBox(height: 18),
                RSectionLabel('Properties · ${props.length}'),
                const SizedBox(height: 8),
                for (final p in props) Padding(padding: const EdgeInsets.only(bottom: 8), child: _propertyCard(p)),
                const SizedBox(height: 10),
                const RSectionLabel('Recent activity'),
                const SizedBox(height: 8),
                _activity(),
                const SizedBox(height: 14),
                Center(child: Text('See all activity', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.tealDeep))),
              ]),
            );
          },
        ),
      ),
    );
  }

  String _serviceLine(Map<String, dynamic> c) => switch (c['status']) {
        'active' => 'Lawn care (bi-weekly)',
        'paused' => 'Paused',
        _ => 'One-time',
      };

  Widget _programTrack() {
    // states: 0 done, 1 now, 2 posted, 3 unposted, 4 future
    const cells = [
      (0, 'raking'), (0, 'raking'), (0, 'leafBlow'), (0, 'leafBlow'),
      (1, 'aeration'), (2, 'aeration'), (3, 'seeding'), (3, 'seeding'),
      (4, 'fertilizing'), (4, 'fertilizing'), (4, 'overseeding'), (4, 'overseeding'),
      (4, 'fertilizing'), (4, 'fertilizing'), (4, 'overseeding'), (4, 'raking'),
    ];
    return Row(children: [
      for (var i = 0; i < cells.length; i++) ...[
        Expanded(child: _trackCell(cells[i].$1, cells[i].$2)),
        if (i < cells.length - 1) const SizedBox(width: 2),
      ],
    ]);
  }

  Widget _trackCell(int state, String phase) {
    final (bg, fg, border) = switch (state) {
      0 => (RColors.teal, Colors.white, null),
      1 => (RColors.teal, Colors.white, null),
      2 => (RColors.tealTint, RColors.tealDeep, RColors.teal),
      3 => (Colors.transparent, const Color(0xFF777777), const Color(0xFF999999)),
      _ => (RColors.paper2, RColors.inkSoft, RColors.border),
    };
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: state == 1 ? const Border(top: BorderSide(color: RColors.lime, width: 3)) : (border != null ? Border.all(color: border, width: state == 3 ? 1 : 0.6) : null),
      ),
      child: Center(child: Icon(phaseIcon(phase), size: 11, color: fg)),
    );
  }

  Widget _contactRow(IconData icon, String text, bool border) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: border ? const Border(bottom: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Row(children: [
          Icon(icon, size: 16, color: RColors.teal),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: RColors.ink))),
          const Icon(Icons.chevron_right, size: 14, color: Color(0xFF888888)),
        ]),
      );

  Widget _propertyCard(Map<String, dynamic> p) => RCard(child: Row(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: RColors.paper2, borderRadius: BorderRadius.circular(11)), child: Icon(p['illustration'] == 'cabin' ? Icons.cabin : Icons.house_rounded, size: 28, color: RColors.teal)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['name'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink)),
          const SizedBox(height: 1),
          Text(p['address'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: RColors.inkMuted)),
          const SizedBox(height: 4),
          Text(p['serviceType'] == 'biweekly' ? 'Lawn care (bi-weekly) · Visit ${p['visitNumber']} of ${p['totalVisits']} · ${p['nextVisitLabel']}' : (p['nextVisitLabel'] ?? ''),
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: p['serviceType'] == 'biweekly' ? RColors.tealDeep : RColors.inkMuted)),
        ])),
        const Icon(Icons.chevron_right, size: 14, color: Color(0xFF888888)),
      ]));

  Widget _activity() => FutureBuilder<List<Visit>>(
        future: _visits,
        builder: (context, snap) {
          final visits = snap.data ?? const <Visit>[];
          if (visits.isEmpty) {
            return RCard(radius: 14, child: Text('No recent activity yet.', style: RText.muted));
          }
          return RCard(radius: 14, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), child: Column(children: [
            for (var i = 0; i < visits.length; i++) _activityRow(visits[i], i > 0),
          ]));
        },
      );

  Widget _activityRow(Visit v, bool border) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(v.date, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.ink)),
            Text(v.crew, style: RText.muted),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Text('Maple Street home · ', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkMuted)),
            Icon(phaseIcon(v.phase), size: 11, color: RColors.tealDeep),
            const SizedBox(width: 3),
            Text(phaseLabel(v.phase), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.tealDeep)),
          ]),
        ]),
      );
}
