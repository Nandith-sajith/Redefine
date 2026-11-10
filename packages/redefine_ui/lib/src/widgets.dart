import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';

import 'actions.dart';
import 'session.dart';
import 'theme.dart';

/// Circular initials avatar; a person glyph stands in for missing initials.
class RAvatar extends StatelessWidget {
  const RAvatar(this.initials, {super.key, this.colorKey = 'lime', this.size = 36});
  final String initials;
  final String colorKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = avatarColors(colorKey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(Icons.person_rounded, size: size * 0.5, color: c.fg)
          : Text(
              initials,
              style: GoogleFonts.plusJakartaSans(
                fontSize: size * 0.33,
                fontWeight: FontWeight.w700,
                color: c.fg,
              ),
            ),
    );
  }
}

/// The "redefine." wordmark.
class RWordmark extends StatelessWidget {
  const RWordmark({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: RColors.tealDeep,
      letterSpacing: -0.3,
    );
    return Text.rich(
      TextSpan(
        text: 'redefine',
        style: style,
        children: [
          TextSpan(
            text: '.',
            style: style.copyWith(color: RColors.lime),
          ),
        ],
      ),
    );
  }
}

/// White rounded card with hairline border.
class RCard extends StatelessWidget {
  const RCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
    this.border,
    this.color,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Border? border;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    // The fill is on the Material and the Container only draws the border, so
    // the ink of a tappable card is not hidden behind an opaque box.
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: shape,
        border: border ?? Border.all(color: RColors.border, width: 0.6),
      ),
      child: child,
    );
    return Material(
      color: color ?? RColors.white,
      borderRadius: shape,
      child: onTap == null ? content : InkWell(borderRadius: shape, onTap: onTap, child: content),
    );
  }
}

/// Section eyebrow ("NEEDS ATTENTION").
class RSectionLabel extends StatelessWidget {
  const RSectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final label = Text(text.toUpperCase(), style: RText.eyebrow);
    if (trailing == null) return label;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [label, trailing!]);
  }
}

/// Small status pill (dot + label).
class RPill extends StatelessWidget {
  const RPill(
    this.label, {
    super.key,
    this.bg = RColors.tealTint,
    this.fg = RColors.tealDeep,
    this.dot,
    this.icon,
  });
  final String label;
  final Color bg, fg;
  final Color? dot;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What was ordered: "PLOUGH" or "PLOUGH + SHOVEL".
class RServiceTag extends StatelessWidget {
  const RServiceTag({super.key, required this.shovel});
  final bool shovel;
  @override
  Widget build(BuildContext context) => RPill(
    serviceLabel(shovel: shovel).toUpperCase(),
    icon: serviceIcon(shovel: shovel),
  );
}

/// The customer-facing name of a job status.
String jobStatusLabel(JobStatus status) => switch (status) {
  JobStatus.open => 'Waiting for crew',
  JobStatus.claimed => 'Crew assigned',
  JobStatus.inProgress => 'In progress',
  JobStatus.done => 'Done',
  JobStatus.cancelled => 'Cancelled',
  JobStatus.unknown => 'Unknown',
};

/// Where a job stands, as a coloured pill.
class RJobStatusPill extends StatelessWidget {
  const RJobStatusPill(this.status, {super.key});
  final JobStatus status;
  @override
  Widget build(BuildContext context) {
    final label = jobStatusLabel(status);
    return switch (status) {
      JobStatus.open => RPill(
        label,
        bg: RColors.amberTint,
        fg: const Color(0xFF7A5514),
        dot: RColors.amber,
      ),
      JobStatus.claimed => RPill(label, dot: RColors.teal),
      JobStatus.inProgress => RPill(
        label,
        bg: RColors.lime,
        fg: RColors.ink,
        dot: RColors.tealDeep,
      ),
      JobStatus.done => RPill(label, icon: Icons.check_rounded),
      JobStatus.cancelled => RPill(label, bg: RColors.dangerTint, fg: RColors.danger),
      JobStatus.unknown => RPill(label, bg: RColors.paper2, fg: RColors.inkMuted),
    };
  }
}

/// The name of a payment status; empty when there is nothing to say yet.
String paymentStatusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.authorized => 'Hold placed',
  PaymentStatus.captured || PaymentStatus.paid => 'Paid',
  PaymentStatus.released => 'Hold released',
  PaymentStatus.failed => 'Payment failed',
  PaymentStatus.due => 'Due',
  PaymentStatus.none || PaymentStatus.unknown => '',
};

/// How a job's payment stands. Takes no space while there is nothing to
/// show (status `none`, or a view such as the crew's that carries no payment).
class RPaymentPill extends StatelessWidget {
  RPaymentPill(PaymentInfo payment, {super.key}) : status = payment.status;

  /// For rows that only carry the status, such as a billing charge.
  const RPaymentPill.status(this.status, {super.key});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final label = paymentStatusLabel(status);
    return switch (status) {
      PaymentStatus.none || PaymentStatus.unknown => const SizedBox.shrink(),
      PaymentStatus.authorized => RPill(
        label,
        bg: RColors.paper2,
        fg: const Color(0xFF555555),
        icon: Icons.lock_outline_rounded,
      ),
      PaymentStatus.captured || PaymentStatus.paid => RPill(label, icon: Icons.check_rounded),
      PaymentStatus.released => RPill(label, bg: RColors.paper2, fg: RColors.inkMuted),
      PaymentStatus.failed => RPill(
        label,
        bg: RColors.dangerTint,
        fg: RColors.danger,
        icon: Icons.error_outline_rounded,
      ),
      PaymentStatus.due => RPill(label, bg: RColors.amberTint, fg: const Color(0xFF7A5514)),
    };
  }
}

/// Neutral paper chip.
class RChip extends StatelessWidget {
  const RChip(
    this.label, {
    super.key,
    this.bg = RColors.paper2,
    this.fg = const Color(0xFF555555),
    this.icon,
    this.iconColor,
  });
  final String label;
  final Color bg, fg;
  final IconData? icon;
  final Color? iconColor;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 4, 10, 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: iconColor ?? fg),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
        ),
      ],
    ),
  );
}

/// An inline message: a notice (teal) or an error (red), with an optional
/// action on the right.
class RBanner extends StatelessWidget {
  const RBanner(
    this.message, {
    super.key,
    this.error = false,
    this.icon,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final bool error;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final fg = error ? RColors.danger : RColors.tealDeep;
    final action = actionLabel;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: error ? RColors.dangerTint : RColors.tealTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon ?? (error ? Icons.error_outline_rounded : Icons.info_outline_rounded),
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.35,
                ),
              ),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(action),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _buttonContent(String label, IconData? icon, bool busy, double iconSize) => Row(
  mainAxisSize: MainAxisSize.min,
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    if (busy) ...[
      SizedBox(
        width: iconSize,
        height: iconSize,
        // Coloured by the button's ProgressIndicatorTheme.
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 10),
    ] else if (icon != null) ...[
      Icon(icon, size: iconSize),
      const SizedBox(width: 8),
    ],
    Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
  ],
);

/// Full-width primary (teal) button. While [busy] it shows a spinner and
/// ignores presses.
class RPrimaryButton extends StatelessWidget {
  const RPrimaryButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.color = RColors.teal,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: RColors.white,
        disabledBackgroundColor: color.withValues(alpha: busy ? 0.75 : 0.35),
        disabledForegroundColor: RColors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      child: ProgressIndicatorTheme(
        data: const ProgressIndicatorThemeData(color: RColors.white),
        child: _buttonContent(label, icon, busy, 16),
      ),
    ),
  );
}

/// Outline (ghost) button. While [busy] it shows a spinner and ignores
/// presses.
class ROutlineButton extends StatelessWidget {
  const ROutlineButton(
    this.label, {
    super.key,
    this.onPressed,
    this.color = RColors.ink,
    this.fullWidth = false,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool fullWidth;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final shown = enabled || busy ? color : color.withValues(alpha: 0.4);
    final btn = OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: shown,
        side: BorderSide(color: shown, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: ProgressIndicatorTheme(
        data: ProgressIndicatorThemeData(color: shown),
        child: _buttonContent(label, icon, busy, 14),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// One entry of the [RAppHeader] account menu.
class RMenuAction {
  const RMenuAction(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// "Hi Lia!" + avatar header row. The avatar opens the account menu: who is
/// signed in, the screen's own [actions], then Sign out.
///
/// [greeting], [initials] and [colorKey] default to the signed-in user from
/// the enclosing [SessionScope].
class RAppHeader extends StatelessWidget {
  const RAppHeader({
    super.key,
    this.greeting,
    this.initials,
    this.colorKey,
    this.actions = const [],
    this.showSignOut = true,
  });
  final String? greeting, initials, colorKey;
  final List<RMenuAction> actions;
  final bool showSignOut;

  static const _signOut = -1;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.maybeOf(context);
    final user = session?.user;
    final firstName = user?.firstName ?? '';
    final color = colorKey ?? user?.color ?? '';
    final avatar = RAvatar(
      initials ?? user?.initials ?? '',
      colorKey: color.isEmpty ? 'lime' : color,
    );
    final canSignOut = showSignOut && session != null;
    final hasEntries = actions.isNotEmpty || canSignOut;
    return Row(
      children: [
        Expanded(
          child: Text(
            greeting ?? (firstName.isEmpty ? 'Hi!' : 'Hi $firstName!'),
            style: RText.h2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        if (user == null && !hasEntries)
          avatar
        else
          PopupMenuButton<int>(
            tooltip: 'Account',
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            borderRadius: BorderRadius.circular(999),
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
            onSelected: (value) {
              if (value == _signOut) {
                _confirmSignOut(context, session!);
              } else {
                actions[value].onTap();
              }
            },
            itemBuilder: (_) => [
              if (user != null) PopupMenuItem<int>(enabled: false, child: _AccountSummary(user)),
              if (user != null && hasEntries) const PopupMenuDivider(),
              for (var i = 0; i < actions.length; i++)
                PopupMenuItem<int>(value: i, child: _MenuRow(actions[i].icon, actions[i].label)),
              if (canSignOut)
                const PopupMenuItem<int>(
                  value: _signOut,
                  child: _MenuRow(Icons.logout_rounded, 'Sign out'),
                ),
            ],
            child: avatar,
          ),
      ],
    );
  }

  static Future<void> _confirmSignOut(BuildContext context, SessionController session) async {
    if (!context.mounted) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Sign out?',
      message: "You'll need to sign in again to use the app on this device.",
      confirmLabel: 'Sign out',
    );
    if (confirmed) await session.signOut();
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary(this.user);
  final AuthUser user;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(user.name, style: RText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(user.email, style: RText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: RColors.inkMuted),
      const SizedBox(width: 12),
      Flexible(
        child: Text(label, style: RText.body, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// Thin rounded progress bar.
class RProgressBar extends StatelessWidget {
  const RProgressBar(
    this.value, {
    super.key,
    this.width = 30,
    this.height = 6,
    this.color = RColors.teal,
    this.track = RColors.paper2,
  });
  final double value, width, height;
  final Color color, track;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: Container(
      width: width,
      height: height,
      color: track,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0, 1),
          child: Container(color: color),
        ),
      ),
    ),
  );
}

enum RStepState { done, current, upcoming }

/// One row of an [RStepTracker].
class RStep {
  const RStep(this.title, {this.subtitle, required this.state});
  final String title;
  final String? subtitle;
  final RStepState state;
}

/// Vertical progress tracker: a marker per step joined by a line.
class RStepTracker extends StatelessWidget {
  const RStepTracker({super.key, required this.steps});
  final List<RStep> steps;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < steps.length; i++) _StepRow(steps[i], last: i == steps.length - 1),
    ],
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow(this.step, {required this.last});
  final RStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final upcoming = step.state == RStepState.upcoming;
    final subtitle = step.subtitle;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                _StepMarker(step.state),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: step.state == RStepState.done ? RColors.teal : RColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: upcoming ? FontWeight.w500 : FontWeight.w700,
                      color: upcoming ? RColors.inkSoft : RColors.ink,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: RText.muted),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker(this.state);
  final RStepState state;

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    return switch (state) {
      RStepState.done => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: RColors.teal, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 14, color: RColors.white),
      ),
      RStepState.current => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: RColors.lime,
          shape: BoxShape.circle,
          border: Border.all(color: RColors.teal, width: 2),
        ),
      ),
      RStepState.upcoming => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: RColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: RColors.border, width: 1.5),
        ),
      ),
    };
  }
}

/// Labelled text input in the design's field style: eyebrow label, bordered
/// white box, optional leading icon and an error line underneath.
///
/// With [obscure] the text is hidden behind a show/hide toggle. A
/// [maxLines] other than 1 makes a fixed-height multi-line box.
class RTextField extends StatefulWidget {
  const RTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.errorText,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.obscure = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.prefixText,
    this.focusNode,
    this.textInputAction,
    this.autofocus = false,
    this.autofillHints,
  });
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final String? errorText;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  /// Called when Enter is pressed in a single-line field.
  final ValueChanged<String>? onSubmitted;
  final String? prefixText;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final Iterable<String>? autofillHints;

  @override
  State<RTextField> createState() => _RTextFieldState();
}

class _RTextFieldState extends State<RTextField> {
  FocusNode? _ownFocus;
  bool _reveal = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(RTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChanged);
      _focus.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _ownFocus)?.removeListener(_onFocusChanged);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final error = w.errorText;
    final hasError = error != null && error.isNotEmpty;
    final focused = _focus.hasFocus;
    final multiline = !w.obscure && w.maxLines != 1;
    final textStyle = GoogleFonts.plusJakartaSans(fontSize: 14, color: RColors.ink);
    final shape = BorderRadius.circular(12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          w.label.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF888888),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 7),
        MouseRegion(
          cursor: w.enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
          child: GestureDetector(
            // The whole box is the click target, not only the line of text.
            behavior: HitTestBehavior.opaque,
            onTap: w.enabled ? _focus.requestFocus : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: w.enabled ? RColors.white : RColors.paper2,
                borderRadius: shape,
              ),
              // Foreground, so a thicker focus border does not shift the text.
              foregroundDecoration: BoxDecoration(
                borderRadius: shape,
                border: Border.all(
                  color: hasError
                      ? RColors.danger
                      : focused
                      ? RColors.teal
                      : RColors.border,
                  width: hasError || focused ? 1.4 : 0.8,
                ),
              ),
              child: Row(
                crossAxisAlignment: multiline
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  if (w.icon != null) ...[
                    Icon(w.icon, size: 17, color: RColors.inkSoft),
                    const SizedBox(width: 10),
                  ],
                  if (w.prefixText != null) ...[
                    Text(w.prefixText!, style: textStyle.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: TextField(
                      controller: w.controller,
                      focusNode: _focus,
                      enabled: w.enabled,
                      autofocus: w.autofocus,
                      obscureText: w.obscure && !_reveal,
                      keyboardType: w.keyboardType,
                      textInputAction: w.textInputAction,
                      inputFormatters: w.inputFormatters,
                      maxLines: multiline ? w.maxLines : 1,
                      maxLength: w.maxLength,
                      autofillHints: w.autofillHints,
                      onChanged: w.onChanged,
                      onSubmitted: w.onSubmitted,
                      cursorColor: RColors.teal,
                      style: textStyle,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: w.hint,
                        hintStyle: textStyle.copyWith(color: RColors.inkSoft),
                      ),
                      // Only a multi-line box has room for the counter.
                      buildCounter:
                          (_, {required currentLength, required maxLength, required isFocused}) =>
                              multiline && maxLength != null
                              ? Text('$currentLength/$maxLength', style: RText.muted)
                              : null,
                    ),
                  ),
                  if (w.obscure) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _reveal ? 'Hide' : 'Show',
                      child: InkResponse(
                        // Mouse only: Tab should go from the field to the next control.
                        canRequestFocus: false,
                        radius: 16,
                        onTap: w.enabled ? () => setState(() => _reveal = !_reveal) : null,
                        child: Icon(
                          _reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 17,
                          color: RColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: RColors.danger,
            ),
          ),
        ],
      ],
    );
  }
}

/// Rebuilds every second with the time passed since [since] (never negative),
/// for running clocks such as "on site for 18 min".
class RElapsed extends StatefulWidget {
  const RElapsed({super.key, required this.since, required this.builder});
  final DateTime since;
  final Widget Function(BuildContext, Duration) builder;

  @override
  State<RElapsed> createState() => _RElapsedState();
}

class _RElapsedState extends State<RElapsed> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.since);
    return widget.builder(context, elapsed.isNegative ? Duration.zero : elapsed);
  }
}

class RNavItem {
  const RNavItem(this.label, this.icon, {this.badge});
  final String label;
  final IconData icon;

  /// A count shown on the icon; hidden when null or 0.
  final int? badge;
}

/// Bottom navigation styled like the designs (surface, top border, teal-deep active).
class RBottomNav extends StatelessWidget {
  const RBottomNav({super.key, required this.items, required this.currentIndex, this.onTap});
  final List<RNavItem> items;
  final int currentIndex;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    // The fill is on the Material so the items' ink shows on top of it.
    return Material(
      color: RColors.surface,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)),
        ),
        padding: const EdgeInsets.only(top: 4, bottom: 8, left: 14, right: 14),
        // Phones draw the app under the gesture bar: keep the items above it.
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: onTap == null ? null : () => onTap!(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});
  final RNavItem item;
  final bool active;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = active ? RColors.tealDeep : const Color(0xFF888888);
    final badge = item.badge ?? 0;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  if (badge > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                        decoration: BoxDecoration(
                          color: RColors.amber,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: RColors.surface, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: RColors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented control (Open | Mine | Done).
class RSegmented extends StatelessWidget {
  const RSegmented({super.key, required this.options, required this.index, this.onChanged});
  final List<String> options;
  final int index;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) {
    final pill = BorderRadius.circular(999);
    return Material(
      color: RColors.paper2,
      borderRadius: pill,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              InkWell(
                borderRadius: pill,
                onTap: onChanged == null ? null : () => onChanged!(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == index ? RColors.white : Colors.transparent,
                    borderRadius: pill,
                  ),
                  child: Text(
                    options[i],
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: i == index ? FontWeight.w700 : FontWeight.w600,
                      color: i == index ? RColors.tealDeep : const Color(0xFF888888),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Centers app content at a phone width when running on a wide (web/desktop)
/// window, with a soft surround — so the apps preview like a phone.
class RPhoneFrame extends StatelessWidget {
  const RPhoneFrame({super.key, required this.child, this.maxWidth = 412});
  final Widget child;
  final double maxWidth;

  static const _margin = 16.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth + 40) return child;
    final framed = Size(maxWidth, math.max(0.0, media.size.height - 2 * _margin));
    return ColoredBox(
      color: const Color(0xFFEDEAE0),
      child: Center(
        child: Container(
          width: maxWidth,
          margin: const EdgeInsets.symmetric(vertical: _margin),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // Screens must see the frame's size, not the window's.
          child: MediaQuery(
            data: media.copyWith(size: framed),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A back row ("‹ Back to ...").
class RBackRow extends StatelessWidget {
  const RBackRow(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.chevron_left, size: 18, color: RColors.ink),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF555555),
          ),
        ),
      ],
    ),
  );
}
