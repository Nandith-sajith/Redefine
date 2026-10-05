import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import 'job_detail.dart';

class JobsHomeScreen extends StatefulWidget {
  const JobsHomeScreen({super.key});
  @override
  State<JobsHomeScreen> createState() => _JobsHomeScreenState();
}

class _JobsHomeScreenState extends State<JobsHomeScreen> {
  late Future<Map<String, dynamic>> _data;

  @override
  void initState() {
    super.initState();
    _data = api.crewJobs(crewId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: RColors.teal));
          }
          final groups = (snap.data!['groups'] as List).cast<Map<String, dynamic>>();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RAppHeader(greeting: 'Hi Marcus!', initials: crewInitials),
              const SizedBox(height: 6),
              Text('Wednesday, May 3', style: RText.muted),
              const SizedBox(height: 16),
              for (final g in groups) _group(g),
            ]),
          );
        },
      ),
    );
  }

  Widget _group(Map<String, dynamic> g) {
    final jobs = (g['jobs'] as List).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${g['label']} · ${g['count']} jobs'.toUpperCase(), style: RText.eyebrow),
          Text('\$${g['total']}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: RColors.teal)),
        ]),
        const SizedBox(height: 8),
        if (jobs.isEmpty)
          RCard(
            radius: 14,
            color: Colors.transparent,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Fri – Sun', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.ink)),
                const SizedBox(height: 2),
                Text('${g['count']} more jobs scheduled', style: RText.muted),
              ]),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF888888)),
            ]),
          )
        else
          for (var i = 0; i < jobs.length; i++) Padding(
            padding: EdgeInsets.only(bottom: i < jobs.length - 1 ? 8 : 0),
            child: _jobCard(jobs[i]),
          ),
      ]),
    );
  }

  Widget _jobCard(Map<String, dynamic> j) {
    return RCard(
      radius: 14,
      onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => JobDetailScreen(job: j))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(child: Text(j['name'], style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink))),
          Text('\$${j['pay']}', style: RText.price),
        ]),
        const SizedBox(height: 5),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(j['address'], style: RText.muted),
          Text(j['time'], style: RText.muted),
        ]),
      ]),
    );
  }
}
