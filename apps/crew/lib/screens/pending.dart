import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import 'accept_job.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});
  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  late Future<List<JobCard>> _jobs;

  @override
  void initState() {
    super.initState();
    _jobs = api.pendingJobs();
  }

  void _reload() => setState(() => _jobs = api.pendingJobs());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<List<JobCard>>(
        future: _jobs,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
          }
          final jobs = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RAppHeader(greeting: 'Hi Marcus!', initials: crewInitials),
              const SizedBox(height: 16),
              Text('Pending jobs', style: RText.h1),
              const SizedBox(height: 4),
              Text('${jobs.length} cards open this week', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted)),
              const SizedBox(height: 16),
              for (final j in jobs) Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(j)),
              const SizedBox(height: 6),
              Center(child: Text('Cards expire if no one claims them by Friday.', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkSoft))),
            ]),
          );
        },
      ),
    );
  }

  Widget _card(JobCard j) {
    final slotsLabel = j.maxCrew == 1 ? '${j.slotsFilled} of 1 slot' : '${j.slotsFilled} of ${j.maxCrew} slots';
    return RCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(child: Text(j.propertyName, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.3))),
          Text('\$${j.payPerCrew}', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: RColors.teal)),
        ]),
        const SizedBox(height: 6),
        Text('${j.address} · ${j.time}', style: RText.muted),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          RChip(phaseLabel(j.phase).toUpperCase(), bg: RColors.tealTint, fg: RColors.tealDeep, icon: phaseIcon(j.phase), iconColor: RColors.tealDeep),
          RChip(slotsLabel),
          RChip(j.goTogether ? 'Go together: yes' : 'Solo OK'),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              final claimed = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(builder: (_) => AcceptJobScreen(job: j)));
              if (claimed == true) _reload();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: RColors.tealDeep,
              side: const BorderSide(color: RColors.teal, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: const Text('Accept · pick a day'),
          ),
        ),
      ]),
    );
  }
}
