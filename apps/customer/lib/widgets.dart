import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

IconData illustrationIcon(String key) => key == 'cabin' ? Icons.cabin : Icons.house_rounded;
Color illustrationColor(String key) => key == 'cabin' ? RColors.slate : RColors.teal;

/// A single property tab card (selected / unselected / add).
class PropertyTab extends StatelessWidget {
  const PropertyTab({super.key, this.name, this.illo, this.selected = false, this.isAdd = false, this.onTap, this.badge = false});
  final String? name;
  final String? illo;
  final bool selected, isAdd, badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (isAdd) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 96,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC5C2B9), width: 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(color: RColors.paper2, shape: BoxShape.circle),
              child: const Icon(Icons.add, size: 16, color: Color(0xFF777777)),
            ),
            const SizedBox(height: 6),
            Text('Add property', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF888888))),
          ]),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 96,
          height: 100,
          decoration: BoxDecoration(
            color: selected ? RColors.tealTint : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? RColors.teal : RColors.border, width: selected ? 1.5 : 0.6),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(illustrationIcon(illo ?? 'house'), size: 46, color: illustrationColor(illo ?? 'house')),
            const SizedBox(height: 4),
            Text(name ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? RColors.tealDeep : const Color(0xFF555555))),
          ]),
        ),
        if (badge)
          Positioned(
            top: 6, right: 6,
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: RColors.lime, shape: BoxShape.circle, border: Border.all(color: RColors.tealTint, width: 1.5))),
          ),
      ]),
    );
  }
}

/// Horizontal property-tab strip used across the customer screens.
class PropertyTabStrip extends StatelessWidget {
  const PropertyTabStrip({super.key, required this.tabs, this.onAdd});
  final List<PropertyTab> tabs;
  final VoidCallback? onAdd;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          for (final t in tabs) Padding(padding: const EdgeInsets.only(right: 8), child: t),
          PropertyTab(isAdd: true, onTap: onAdd),
        ],
      ),
    );
  }
}
