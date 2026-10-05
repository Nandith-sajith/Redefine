import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';

class PayScreen extends StatefulWidget {
  const PayScreen({super.key});
  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  late Future<Map<String, dynamic>> _pay;

  @override
  void initState() {
    super.initState();
    _pay = api.crewPay(crewId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _pay,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
          }
          final p = snap.data!;
          final payouts = (p['payouts'] as List).cast<Map<String, dynamic>>();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RAppHeader(greeting: 'Hi Marcus!', initials: crewInitials),
              const SizedBox(height: 18),
              RCard(
                radius: 18,
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('EARNED THIS WEEK', style: RText.eyebrow),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('\$${p['earnedThisWeek']}', style: GoogleFonts.plusJakartaSans(fontSize: 48, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -1.5, height: 1)),
                    const SizedBox(width: 8),
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('/ \$${p['expected']} expected', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: RColors.inkMuted))),
                  ]),
                  const SizedBox(height: 12),
                  RProgressBar((p['progress'] as num).toDouble(), width: double.infinity, height: 6),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${p['jobsDone']} of ${p['jobsTotal']} jobs done', style: RText.muted),
                    Text('${p['payoutLabel']}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.ink)),
                  ]),
                  const SizedBox(height: 8),
                  Text('Bi-weekly cycle · payouts every 2 weeks', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkSoft)),
                ]),
              ),
              const SizedBox(height: 14),
              RCard(
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('EARNED TODAY', style: RText.eyebrow),
                    const SizedBox(height: 4),
                    Text('${p['jobsTodayDone']} of ${p['jobsTodayTotal']} jobs done', style: RText.muted),
                  ]),
                  Text('\$${p['earnedToday']}', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: RColors.teal, letterSpacing: -0.4)),
                ]),
              ),
              const SizedBox(height: 18),
              const RSectionLabel('Recent payouts'),
              const SizedBox(height: 8),
              RCard(
                radius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                child: Column(children: [
                  for (var i = 0; i < payouts.length; i++) _payoutRow(payouts[i], i > 0),
                ]),
              ),
              const SizedBox(height: 16),
              Center(child: Text('View all payouts', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.tealDeep))),
            ]),
          );
        },
      ),
    );
  }

  Widget _payoutRow(Map<String, dynamic> po, bool border) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)) : null),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(po['range'], style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: RColors.ink)),
            const SizedBox(height: 3),
            Row(children: [
              const CircleAvatar(radius: 5.5, backgroundColor: RColors.teal, child: Icon(Icons.check, size: 7, color: Colors.white)),
              const SizedBox(width: 5),
              Text(po['paid'], style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: RColors.tealDeep)),
            ]),
          ]),
          Text('\$${po['amount']}', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.3)),
        ]),
      );
}
