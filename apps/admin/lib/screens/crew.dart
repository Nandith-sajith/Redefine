import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';
import '../widgets/job_widgets.dart' show amberInk;
import 'crew_member.dart';

typedef _CrewLists = ({
  List<CrewMember> active,
  List<CrewMember> pending,
  List<CrewMember> rejected,
});

/// The Crew tab: applications to decide, the approved crew with what each is
/// owed, and the people who were turned down.
class CrewScreen extends StatefulWidget {
  const CrewScreen({super.key, required this.active, required this.onChanged});

  /// Whether this tab is the one in front.
  final bool active;

  /// Called after an approval or rejection: the shell's badges depend on it.
  final VoidCallback onChanged;

  @override
  State<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends State<CrewScreen> with BusyState<CrewScreen> {
  late final RLiveController<_CrewLists> _crew = RLiveController(() => api.crew());

  /// The member being approved or rejected, and which of the two.
  String? _deciding;
  bool _approving = false;
  bool _showRejected = false;

  @override
  void dispose() {
    _crew.dispose();
    super.dispose();
  }

  Future<void> _approve(CrewMember member) async {
    if (busy) return;
    setState(() {
      _deciding = member.id;
      _approving = true;
    });
    await run(
      () => api.approveCrew(member.id),
      success: '${member.name} is approved and can accept jobs',
    );
    _afterDecision();
  }

  Future<void> _reject(CrewMember member) async {
    if (busy) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Reject ${member.name}?',
      message:
          'They will not be able to accept jobs. You can still approve them later from '
          'the Rejected list.',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (!confirmed || !mounted || busy) return;
    setState(() {
      _deciding = member.id;
      _approving = false;
    });
    await run(() => api.rejectCrew(member.id), success: '${member.name} was rejected');
    _afterDecision();
  }

  // Also after a failure: someone else may have decided in the meantime.
  void _afterDecision() {
    if (!mounted) return;
    setState(() => _deciding = null);
    _crew.refresh(silent: true);
    widget.onChanged();
  }

  void _open(CrewMember member) => pushScreen<void>(context, CrewMemberScreen(member: member));

  @override
  Widget build(BuildContext context) => RLive<_CrewLists>(
    controller: _crew,
    active: widget.active,
    pollEvery: const Duration(seconds: 30),
    padding: tabPadding,
    builder: (context, crew) => _body(crew),
  );

  Widget _body(_CrewLists crew) {
    final everyone = [...crew.active, ...crew.pending, ...crew.rejected];
    final unpaid = everyone.fold<int>(0, (sum, member) => sum + member.unpaidTotal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Crew', style: RText.h1),
        const SizedBox(height: 4),
        Text(
          '${crew.active.length} active · ${crew.pending.length} pending · ${money(unpaid)} unpaid',
          style: RText.muted,
        ),
        const SizedBox(height: 18),
        if (crew.pending.isNotEmpty) ...[
          const RSectionLabel('Pending approval'),
          const SizedBox(height: 14),
          for (final member in crew.pending)
            Padding(padding: const EdgeInsets.only(bottom: 16), child: _pendingCard(member)),
          const SizedBox(height: 2),
        ],
        const RSectionLabel('Active crew'),
        const SizedBox(height: 8),
        if (crew.active.isEmpty)
          const RCard(
            padding: EdgeInsets.zero,
            child: REmptyState(
              icon: Icons.person_outline,
              title: 'No approved crew yet',
              message: 'Crew members sign up in the crew app, then wait here for your approval.',
            ),
          )
        else
          ListCard(radius: 14, children: [for (final member in crew.active) _activeRow(member)]),
        if (crew.rejected.isNotEmpty) ...[
          const SizedBox(height: 18),
          ListCard(
            radius: 14,
            children: [
              ListRow(
                onTap: () => setState(() => _showRejected = !_showRejected),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rejected (${crew.rejected.length})',
                        style: RText.title.copyWith(fontSize: 13),
                      ),
                    ),
                    Icon(
                      _showRejected ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: const Color(0xFF888888),
                    ),
                  ],
                ),
              ),
              if (_showRejected)
                for (final member in crew.rejected) _rejectedRow(member),
            ],
          ),
        ],
      ],
    );
  }

  Widget _pendingCard(CrewMember member) {
    final deciding = _deciding == member.id;
    final applied = member.appliedAt;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: RColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: RColors.lime, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PersonRow(
                initials: member.initials,
                colorKey: member.color.isEmpty ? 'teal' : member.color,
                name: member.name,
                subtitle: applied == null
                    ? 'Applied to join the crew'
                    : 'Applied ${fmtAgo(applied)}',
                avatarSize: 44,
              ),
              if (member.email.isNotEmpty || member.phone.isNotEmpty) ...[
                const SizedBox(height: 12),
                ContactCard(email: member.email, phone: member.phone),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  ROutlineButton(
                    'Reject',
                    color: const Color(0xFF777777),
                    busy: deciding && !_approving,
                    onPressed: busy ? null : () => _reject(member),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RPrimaryButton(
                      'Approve',
                      busy: deciding && _approving,
                      onPressed: busy ? null : () => _approve(member),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: -9,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: RColors.lime,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'NEW APPLICATION',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: RColors.ink,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _activeRow(CrewMember member) => ListRow(
    onTap: () => _open(member),
    child: PersonRow(
      initials: member.initials,
      colorKey: member.color,
      name: member.name,
      subtitle:
          '${countOf(member.jobsThisWeek, 'job')} this week · ${money(member.earnedThisWeek)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (member.unpaidTotal > 0) ...[
            RChip('${money(member.unpaidTotal)} UNPAID', bg: RColors.amberTint, fg: amberInk),
            const SizedBox(width: 6),
          ],
          rowChevron,
        ],
      ),
    ),
  );

  Widget _rejectedRow(CrewMember member) => ListRow(
    onTap: () => _open(member),
    child: PersonRow(
      initials: member.initials,
      colorKey: 'paper',
      name: member.name,
      subtitle: member.unpaidTotal > 0 ? '${money(member.unpaidTotal)} unpaid' : member.email,
      trailing: ROutlineButton(
        'Approve',
        color: RColors.tealDeep,
        busy: _deciding == member.id,
        onPressed: busy ? null : () => _approve(member),
      ),
    ),
  );
}
