import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'shell.dart';

/// What a signed-in crew member sees, by approval status: the app once the
/// office has approved them, otherwise a page that explains where they stand.
class CrewGate extends StatefulWidget {
  const CrewGate({super.key});

  @override
  State<CrewGate> createState() => _CrewGateState();
}

class _CrewGateState extends State<CrewGate> {
  CrewStatus? _status;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final status = SessionScope.of(context).user?.crewStatus;
    if (_started && status != _status) {
      // Whatever is pushed on top (a job page, a dialog) belongs to the
      // screen that is being replaced.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
    _started = true;
    _status = status;
  }

  @override
  Widget build(BuildContext context) => switch (_status) {
    CrewStatus.active => const CrewShell(),
    CrewStatus.rejected => const NotApprovedScreen(),
    _ => const AwaitingApprovalScreen(),
  };
}

/// A new crew member waiting for the office. Re-checks on its own and gives
/// way to the app the moment the application is approved.
class AwaitingApprovalScreen extends StatelessWidget {
  const AwaitingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ApprovalPage(
    status: CrewStatus.pending,
    pill: RPill(
      'AWAITING APPROVAL',
      bg: RColors.amberTint,
      fg: Color(0xFF7A5514),
      icon: Icons.hourglass_top_rounded,
    ),
    title: 'Your application is with the office',
    message:
        'The office reviews every crew application before any plough requests are shown. '
        'This page checks for you and opens the app as soon as you are approved.',
    steps: [
      RStep('Application sent', state: RStepState.done),
      RStep('The office reviews it', state: RStepState.current),
      RStep('You start accepting plough requests', state: RStepState.upcoming),
    ],
    pollEvery: Duration(seconds: 20),
    unchanged: 'Not approved yet. This page keeps checking for you.',
  );
}

/// A crew member the office turned down (or removed from the crew).
class NotApprovedScreen extends StatelessWidget {
  const NotApprovedScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ApprovalPage(
    status: CrewStatus.rejected,
    pill: RPill(
      'NOT APPROVED',
      bg: RColors.dangerTint,
      fg: RColors.danger,
      icon: Icons.block_rounded,
    ),
    title: 'Your application was not approved',
    message:
        'The office did not approve this crew account, so plough requests and pay are '
        'not available. If you think this is a mistake, get in touch with the office.',
    unchanged: 'Nothing has changed: this account is still not approved.',
  );
}

class _ApprovalPage extends StatefulWidget {
  const _ApprovalPage({
    required this.status,
    required this.pill,
    required this.title,
    required this.message,
    required this.unchanged,
    this.steps = const [],
    this.pollEvery,
  });

  /// The approval status this page stands for.
  final CrewStatus status;
  final Widget pill;
  final String title, message;

  /// Said after "Check again" when the status is still [status].
  final String unchanged;
  final List<RStep> steps;
  final Duration? pollEvery;

  @override
  State<_ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<_ApprovalPage> with BusyState<_ApprovalPage> {
  // Re-reading the user moves the session, which is what the gate watches.
  final _user = RLiveController<AuthUser?>(() async {
    await session.refreshUser();
    return session.user;
  });

  @override
  void initState() {
    super.initState();
    _user.setData(session.user);
  }

  @override
  void dispose() {
    _user.dispose();
    super.dispose();
  }

  Future<void> _checkAgain() async {
    final checked = await run(() async {
      await session.refreshUser();
      return true;
    });
    if (checked == true && mounted && session.user?.crewStatus == widget.status) {
      showRSnack(context, widget.unchanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: RLive<AuthUser?>(
          controller: _user,
          pollEvery: widget.pollEvery,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          builder: (context, user) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RWordmark(),
              const SizedBox(height: 24),
              widget.pill,
              const SizedBox(height: 10),
              Text(
                widget.title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: RColors.ink,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: RColors.inkMuted,
                  height: 1.5,
                ),
              ),
              if (widget.steps.isNotEmpty) ...[
                const SizedBox(height: 22),
                RCard(child: RStepTracker(steps: widget.steps)),
              ],
              if (user != null) ...[
                const SizedBox(height: 14),
                const RSectionLabel('Signed in as'),
                const SizedBox(height: 8),
                _Applicant(user),
              ],
              const SizedBox(height: 22),
              RPrimaryButton(
                'Check again',
                icon: Icons.refresh_rounded,
                busy: busy,
                onPressed: _checkAgain,
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: busy ? null : session.signOut,
                  style: TextButton.styleFrom(
                    foregroundColor: RColors.inkMuted,
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Applicant extends StatelessWidget {
  const _Applicant(this.user);
  final AuthUser user;

  @override
  Widget build(BuildContext context) => RCard(
    radius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        RAvatar(user.initials, colorKey: user.color.isEmpty ? 'lime' : user.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: RText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                user.phone.isEmpty ? user.email : '${user.email} · ${user.phone}',
                style: RText.muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
