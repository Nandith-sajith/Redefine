import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import 'post_card.dart';
import 'quote_detail.dart';

const _attnIcons = {'quote': Icons.chat_bubble_outline, 'crew': Icons.person_outline, 'card': Icons.assignment_outlined};
const _crewInitials = {'crew-marcus': 'MR', 'crew-jordan': 'JP', 'crew-sam': 'SC', 'crew-pete': 'PL', 'crew-tasha': 'TR'};
const _crewColors = {'crew-marcus': 'lime', 'crew-jordan': 'teal', 'crew-sam': 'paper', 'crew-pete': 'paper', 'crew-tasha': 'teal'};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>> _data;

  @override
  void initState() {
    super.initState();
    _data = api.adminDashboard();
  }

  void _reload() => setState(() => _data = api.adminDashboard());

  Future<void> _openQuote() async {
    final quotes = await api.quotes(status: 'pending');
    if (!mounted || quotes.isEmpty) return;
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: quotes.first.id)));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
          final d = snap.data!;
          final attn = (d['needsAttention'] as List).cast<Map<String, dynamic>>();
          final tw = d['thisWeek'] as Map<String, dynamic>;
          final toPost = (tw['toPost'] as List).cast<Map<String, dynamic>>();
          final today = (d['todaysJobs'] as List).cast<Map<String, dynamic>>();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RAppHeader(greeting: 'Hi Lia!', initials: adminInitials),
              const SizedBox(height: 16),
              Text(d['date'] ?? '', style: RText.h1),
              const SizedBox(height: 4),
              Text(d['summary'] ?? '', style: RText.muted),
              const SizedBox(height: 18),
              const RSectionLabel('Needs attention'),
              const SizedBox(height: 8),
              for (var i = 0; i < attn.length; i++) Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _attnCard(attn[i], i == 0),
              ),
              const SizedBox(height: 10),
              RSectionLabel('This week', trailing: Text('View posting board →', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.tealDeep))),
              const SizedBox(height: 8),
              _thisWeekCard(tw),
              const SizedBox(height: 8),
              _toPostList(toPost),
              const SizedBox(height: 18),
              const RSectionLabel("Today's jobs"),
              const SizedBox(height: 8),
              _todayCard(today),
            ]),
          );
        },
      ),
    );
  }

  Widget _attnCard(Map<String, dynamic> a, bool first) {
    return RCard(
      onTap: first ? _openQuote : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: RColors.paper2, borderRadius: BorderRadius.circular(8)), child: Icon(_attnIcons[a['icon']] ?? Icons.circle, size: 16, color: RColors.teal)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['title'], style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: RColors.ink)),
          const SizedBox(height: 1),
          Text(a['sub'], style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkMuted)),
        ])),
        const Icon(Icons.chevron_right, size: 16, color: Color(0xFF888888)),
      ]),
    );
  }

  Widget _thisWeekCard(Map<String, dynamic> tw) {
    final filled = (tw['filled'] as num).toInt(), total = (tw['total'] as num).toInt();
    return RCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tw['label'], style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: RColors.ink)),
          const SizedBox(height: 2),
          Row(children: [
            Text('$filled of $total jobs filled', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: RColors.tealDeep)),
            Text(' · ${total - filled} unfilled', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkMuted)),
          ]),
        ]),
        RProgressBar(filled / total),
      ]),
    );
  }

  Widget _toPostList(List<Map<String, dynamic>> toPost) {
    if (toPost.isEmpty) return const SizedBox.shrink();
    return RCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Column(children: [
        for (var i = 0; i < toPost.length; i++) _postRow(toPost[i]['name'], i > 0),
      ]),
    );
  }

  Widget _postRow(String name, bool border) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.ink)),
            const SizedBox(height: 4),
            const RChip('TO POST', icon: Icons.circle, iconColor: Color(0xFF999999)),
          ]),
          _postButton(name),
        ]),
      );

  Widget _postButton(String name) => OutlinedButton(
        onPressed: () async {
          await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PostCardScreen(propertyName: name)));
          _reload();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF777777),
          side: const BorderSide(color: Color(0xFF999999)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        child: const Text('+ Post'),
      );

  Widget _todayCard(List<Map<String, dynamic>> jobs) {
    return RCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(children: [
        for (var i = 0; i < jobs.length; i++) _todayRow(jobs[i], i > 0),
      ]),
    );
  }

  Widget _todayRow(Map<String, dynamic> j, bool border) {
    final status = j['status'];
    final crewIds = (j['crewIds'] as List).cast<String>();
    Widget statusWidget;
    if (status == 'inProgress') {
      statusWidget = const RPill('NOW', dot: RColors.lime);
    } else if ((j['eta'] as String?)?.isNotEmpty == true) {
      statusWidget = Text(j['eta'], style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.inkMuted));
    } else {
      statusWidget = const SizedBox(width: 1);
    }
    Widget trailing;
    if (crewIds.isEmpty) {
      trailing = _postButton(j['name']);
    } else {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        for (final id in crewIds) Padding(padding: const EdgeInsets.only(left: 2), child: RAvatar(_crewInitials[id] ?? '?', colorKey: _crewColors[id] ?? 'paper', size: 22)),
      ]);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
      child: Row(children: [
        SizedBox(width: 60, child: statusWidget),
        Expanded(child: Text(j['name'], style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.ink))),
        trailing,
      ]),
    );
  }
}
