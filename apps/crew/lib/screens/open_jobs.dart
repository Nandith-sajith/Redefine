import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../crew_data.dart';
import '../job_actions.dart';
import '../logic.dart';
import '../widgets.dart';
import 'job_detail.dart';

/// The Open tab: plough requests nobody has accepted yet, oldest first. The
/// first crew member to accept one takes it.
class OpenJobsScreen extends StatefulWidget {
  const OpenJobsScreen({super.key, required this.data, required this.active});
  final CrewData data;
  final bool active;

  @override
  State<OpenJobsScreen> createState() => _OpenJobsScreenState();
}

class _OpenJobsScreenState extends State<OpenJobsScreen> {
  CrewData get _data => widget.data;

  @override
  void didUpdateWidget(OpenJobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list polls on every tab; coming to this one should not wait for it.
    if (widget.active && !oldWidget.active) _data.open.refresh(silent: true);
  }

  void _open(Job job) => openJobDetail(context, _data, jobId: job.id, initial: job);

  /// The accepted job now lives on the Jobs tab; its page opens on top,
  /// unless a job page is already open (two requests accepted in a row).
  void _accepted(Job job) {
    // The answer may arrive after the app has moved on (signed out, sent to
    // the approval gate): the job is accepted, but there is nowhere to show it.
    if (!mounted) return;
    // Asked of the route itself: the inherited value lags a frame behind.
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    _data.goTo(CrewTab.jobs);
    if (onTop) _open(job);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: RAppHeader()),
          Expanded(
            // Not tied to `active`: the shell's badge counts this list.
            child: RLive<List<Job>>(
              controller: _data.open,
              pollEvery: const Duration(seconds: 10),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              builder: (context, jobs) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Open requests', style: RText.h1),
                  const SizedBox(height: 4),
                  Text(
                    jobs.isEmpty
                        ? 'Nobody is waiting for a plough'
                        : '${countLabel(jobs.length, 'request')} waiting · the first to accept takes it',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  if (jobs.isEmpty)
                    const REmptyState(
                      icon: Icons.ac_unit_rounded,
                      title: 'No open requests right now',
                      message: 'New requests appear here automatically.',
                    ),
                  for (final job in jobs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OpenJobCard(
                        key: ValueKey(job.id),
                        job: job,
                        data: _data,
                        onTap: () => _open(job),
                        onAccepted: _accepted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenJobCard extends StatefulWidget {
  const _OpenJobCard({
    super.key,
    required this.job,
    required this.data,
    required this.onTap,
    required this.onAccepted,
  });
  final Job job;
  final CrewData data;
  final VoidCallback onTap;
  final ValueChanged<Job> onAccepted;

  @override
  State<_OpenJobCard> createState() => _OpenJobCardState();
}

class _OpenJobCardState extends State<_OpenJobCard>
    with BusyState<_OpenJobCard>, JobActions<_OpenJobCard> {
  @override
  CrewData get crewData => widget.data;

  Future<void> _accept() async {
    // The screen navigates, not this card: it leaves the list with its job.
    final onAccepted = widget.onAccepted;
    final job = await acceptJob(widget.job.id);
    if (job != null) onAccepted(job);
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final requestedAt = job.requestedAt;
    return RCard(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobTitleRow(
            job.propertyName,
            size: 16,
            trailing: Text('You earn ${money(job.crewPay)}', style: RText.price),
          ),
          const SizedBox(height: 6),
          MutedLine(job.address),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RServiceTag(shovel: job.shovel),
              if (requestedAt != null)
                RChip('requested ${fmtAgo(requestedAt)}', icon: Icons.schedule),
            ],
          ),
          if (job.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              job.note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF444444),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ROutlineButton(
            'Accept',
            icon: Icons.check_rounded,
            color: RColors.tealDeep,
            fullWidth: true,
            busy: busy,
            onPressed: _accept,
          ),
        ],
      ),
    );
  }
}
