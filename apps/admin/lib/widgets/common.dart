// Small pieces shared by the admin screens: navigation and loading helpers,
// the pushed-page frame, list cards, copyable rows, tiles and filter pills.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `Monday, October 5`.
String fmtLongDate(DateTime date) {
  final d = date.toLocal();
  return '${_weekdays[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}';
}

/// `1 job`, `3 jobs`; [many] overrides the plain `s` plural.
String countOf(int n, String one, [String? many]) => '$n ${n == 1 ? one : many ?? '${one}s'}';

/// The first word of a person's name, for short status lines.
String firstNameOf(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
}

/// Pushes [screen] on the app's navigator.
Future<T?> pushScreen<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => screen));

/// Awaits two calls made at the same time. Fails with the first error as it
/// was thrown, so an `ApiException` stays one.
Future<(A, B)> both<A, B>(Future<A> a, Future<B> b) async {
  final results = await Future.wait<Object?>([a, b]);
  return (results[0] as A, results[1] as B);
}

/// Copies [value] to the clipboard and says so. [what] names it: "Email".
Future<void> copyText(BuildContext context, String value, {required String what}) async {
  try {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) showRSnack(context, '$what copied');
  } catch (_) {
    // Browsers may refuse clipboard access.
    if (context.mounted) {
      showRSnack(context, "Couldn't copy the ${what.toLowerCase()}.", error: true);
    }
  }
}

/// The frame of every pushed screen: a back row, then [child] filling the
/// rest (usually an `RLive`).
class PushedPage extends StatelessWidget {
  const PushedPage({super.key, required this.child, this.backLabel = 'Back', this.canLeave = true});
  final Widget child;
  final String backLabel;

  /// False while the page has to stay up, such as until a request whose
  /// result it hands back has answered: the back row is disabled and the
  /// system's back does nothing.
  final bool canLeave;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: canLeave,
    child: Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 20, 0),
              child: Opacity(
                opacity: canLeave ? 1 : 0.4,
                child: RBackRow(
                  backLabel,
                  onTap: canLeave ? () => Navigator.of(context).maybePop() : null,
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

/// Padding of the scrolling content of a pushed screen.
const pagePadding = EdgeInsets.fromLTRB(20, 14, 20, 28);

/// Padding of the scrolling content of a tab.
const tabPadding = EdgeInsets.fromLTRB(20, 12, 20, 24);

/// A white card of rows separated by hairlines. Unlike a padded `RCard`, the
/// rows reach the card's edge, so a tappable row inks from side to side.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children, this.radius = 16});
  final List<Widget> children;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
    color: RColors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: RColors.border, width: 0.6),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 0.6, thickness: 0.6, color: RColors.borderSoft),
          children[i],
        ],
      ],
    ),
  );
}

/// One row of a [ListCard]; tappable when [onTap] is given.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

/// A contact detail in a [ListCard]. Tapping copies it to the clipboard.
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.icon, required this.value, required this.what});
  final IconData icon;
  final String value;

  /// What the value is, for the confirmation: "Email", "Phone".
  final String what;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Copy ${what.toLowerCase()}',
    child: ListRow(
      onTap: () => copyText(context, value, what: what),
      child: Row(
        children: [
          Icon(icon, size: 16, color: RColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, style: RText.body, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.copy_rounded, size: 14, color: RColors.inkSoft),
        ],
      ),
    ),
  );
}

/// The email and phone of a person as copyable rows; nothing when both are
/// unknown.
class ContactCard extends StatelessWidget {
  const ContactCard({super.key, required this.email, required this.phone});
  final String email, phone;

  @override
  Widget build(BuildContext context) {
    if (email.isEmpty && phone.isEmpty) return const SizedBox.shrink();
    return ListCard(
      radius: 14,
      children: [
        if (email.isNotEmpty) ContactRow(icon: Icons.mail_outline, value: email, what: 'Email'),
        if (phone.isNotEmpty) ContactRow(icon: Icons.phone_outlined, value: phone, what: 'Phone'),
      ],
    );
  }
}

/// A number with a label under it; tappable when [onTap] is given.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.valueColor = RColors.ink,
  });
  final String label, value;
  final VoidCallback? onTap;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => RCard(
    radius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    onTap: onTap,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: RText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (onTap != null) const Icon(Icons.chevron_right, size: 16, color: RColors.inkSoft),
      ],
    ),
  );
}

/// One choice of a filter row: tinted when selected, outlined otherwise.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
      side: selected ? BorderSide.none : const BorderSide(color: RColors.border, width: 0.8),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? RColors.tealTint : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? RColors.tealDeep : const Color(0xFF555555),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A wrapping row of [FilterPill]s.
class FilterRow extends StatelessWidget {
  const FilterRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: children);
}

/// A small teal text action ("Show all", "View customer").
class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, required this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: RColors.tealDeep,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (icon != null) ...[const SizedBox(width: 4), Icon(icon, size: 14)],
      ],
    ),
  );
}

/// A label on the left and its value on the right.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.strong = false, this.valueColor});
  final String label, value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final weight = strong ? FontWeight.w700 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: RText.body.copyWith(
                fontWeight: weight,
                color: strong ? RColors.ink : RColors.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sized to its text, so it sits against the right edge; the label
          // takes what is left.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: RText.body.copyWith(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                color: valueColor ?? RColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width card holding one quiet sentence ("No payouts yet.").
class TextCard extends StatelessWidget {
  const TextCard(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: RCard(radius: 14, child: Text(text, style: RText.muted.copyWith(height: 1.45))),
  );
}

/// The rounded illustration tile of a property.
class PropertyIcon extends StatelessWidget {
  const PropertyIcon(this.illustration, {super.key, this.size = 52});
  final String illustration;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: RColors.paper2,
      borderRadius: BorderRadius.circular(size * 0.21),
    ),
    child: Icon(
      illustrationIcon(illustration),
      size: size * 0.54,
      color: illustrationColor(illustration),
    ),
  );
}

/// A person: avatar, name and a line under it.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.initials,
    required this.colorKey,
    required this.name,
    this.subtitle,
    this.trailing,
    this.avatarSize = 38,
  });
  final String initials, colorKey, name;
  final String? subtitle;
  final Widget? trailing;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Row(
      children: [
        RAvatar(initials, colorKey: colorKey.isEmpty ? 'paper' : colorKey, size: avatarSize),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: RText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: RText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// The chevron at the end of a row that opens something.
const rowChevron = Icon(Icons.chevron_right, size: 16, color: Color(0xFF888888));
