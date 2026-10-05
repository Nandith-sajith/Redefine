import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme.dart';

/// Circular initials avatar.
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
      child: Text(initials,
          style: GoogleFonts.plusJakartaSans(
              fontSize: size * 0.33, fontWeight: FontWeight.w700, color: c.fg)),
    );
  }
}

/// White rounded card with hairline border.
class RCard extends StatelessWidget {
  const RCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 16, this.border, this.color, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Border? border;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? RColors.white,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: RColors.border, width: 0.6),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: card);
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
  const RPill(this.label, {super.key, this.bg = RColors.tealTint, this.fg = RColors.tealDeep, this.dot, this.icon});
  final String label;
  final Color bg, fg;
  final Color? dot;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 6)],
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// Phase tag (teal-tint, phase icon + label).
class RPhaseTag extends StatelessWidget {
  const RPhaseTag(this.phase, {super.key, this.dense = false});
  final String phase;
  final bool dense;
  @override
  Widget build(BuildContext context) => RPill(
        'PHASE · ${phaseLabel(phase).toUpperCase()}',
        icon: phaseIcon(phase),
      );
}

/// Neutral paper chip.
class RChip extends StatelessWidget {
  const RChip(this.label, {super.key, this.bg = RColors.paper2, this.fg = const Color(0xFF555555), this.icon, this.iconColor});
  final String label;
  final Color bg, fg;
  final IconData? icon;
  final Color? iconColor;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 4, 10, 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: iconColor ?? fg), const SizedBox(width: 5)],
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
        ]),
      );
}

/// Full-width primary (teal) button.
class RPrimaryButton extends StatelessWidget {
  const RPrimaryButton(this.label, {super.key, this.onPressed, this.icon, this.color = RColors.teal});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: RColors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
            Text(label),
          ]),
        ),
      );
}

/// Outline (ghost) button.
class ROutlineButton extends StatelessWidget {
  const ROutlineButton(this.label, {super.key, this.onPressed, this.color = RColors.ink, this.fullWidth = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool fullWidth;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 6)],
        Text(label),
      ]),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// "Hi Lia!" + avatar header row.
class RAppHeader extends StatelessWidget {
  const RAppHeader({super.key, required this.greeting, required this.initials, this.colorKey = 'lime'});
  final String greeting, initials, colorKey;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(greeting, style: RText.h2),
          RAvatar(initials, colorKey: colorKey),
        ],
      );
}

/// Thin rounded progress bar.
class RProgressBar extends StatelessWidget {
  const RProgressBar(this.value, {super.key, this.width = 30, this.height = 6, this.color = RColors.teal, this.track = RColors.paper2});
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

class RNavItem {
  const RNavItem(this.label, this.icon, {this.badge});
  final String label;
  final IconData icon;
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
    return Container(
      decoration: const BoxDecoration(
        color: RColors.surface,
        border: Border(top: BorderSide(color: RColors.borderSoft, width: 0.6)),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 14, left: 14, right: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavButton(item: items[i], active: i == currentIndex, onTap: () => onTap?.call(i)),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});
  final RNavItem item;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = active ? RColors.tealDeep : const Color(0xFF888888);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(item.icon, size: 22, color: color),
            if (item.badge != null)
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
                  child: Text('${item.badge}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 8, fontWeight: FontWeight.w700, color: RColors.white)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          Text(item.label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}

/// Segmented control (Timeline | Week | Month).
class RSegmented extends StatelessWidget {
  const RSegmented({super.key, required this.options, required this.index, this.onChanged});
  final List<String> options;
  final int index;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: RColors.paper2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged?.call(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: i == index ? RColors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(options[i],
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w600,
                        color: i == index ? RColors.tealDeep : const Color(0xFF888888))),
              ),
            ),
        ]),
      );
}

/// Centers app content at a phone width when running on a wide (web/desktop)
/// window, with a soft surround — so the apps preview like a phone.
class RPhoneFrame extends StatelessWidget {
  const RPhoneFrame({super.key, required this.child, this.maxWidth = 412});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > maxWidth + 40;
    if (!wide) return child;
    return ColoredBox(
      color: const Color(0xFFEDEAE0),
      child: Center(
        child: Container(
          width: maxWidth,
          margin: const EdgeInsets.symmetric(vertical: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: child,
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.chevron_left, size: 18, color: RColors.ink),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF555555))),
        ]),
      );
}
