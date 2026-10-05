import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Redefine design tokens — pulled straight from the Pencil designs.
class RColors {
  static const teal = Color(0xFF0E6D55);
  static const tealDeep = Color(0xFF0A5746);
  static const tealTint = Color(0xFFE0F2EC);
  static const lime = Color(0xFFC8EE3A);
  static const page = Color(0xFFFAF8F2);
  static const paper = Color(0xFFEFEBE0);
  static const paper2 = Color(0xFFF1EFE8);
  static const surface = Color(0xFFFBFAF7);
  static const ink = Color(0xFF1A1A1A);
  static const inkMuted = Color(0xFF777777);
  static const inkSoft = Color(0xFF999999);
  static const border = Color(0xFFE5E2D9);
  static const borderSoft = Color(0xFFEFEDE5);
  static const white = Color(0xFFFFFFFF);
  static const amber = Color(0xFFC58D2C);
  static const amberTint = Color(0xFFFFF3E0);
  static const slate = Color(0xFF5C7A99);
}

/// Avatar / chip colour pairs keyed by the design's colour names.
({Color bg, Color fg}) avatarColors(String key) {
  switch (key) {
    case 'lime':
      return (bg: RColors.lime, fg: RColors.ink);
    case 'teal':
      return (bg: RColors.tealTint, fg: RColors.tealDeep);
    default:
      return (bg: RColors.paper2, fg: const Color(0xFF555555));
  }
}

/// Maps a program phase to a Material icon.
IconData phaseIcon(String phase) {
  switch (phase) {
    case 'raking':
      return Icons.cleaning_services_outlined;
    case 'leafBlow':
      return Icons.air;
    case 'seeding':
      return Icons.eco_outlined;
    case 'fertilizing':
      return Icons.water_drop_outlined;
    case 'overseeding':
      return Icons.grass;
    case 'aeration':
    default:
      return Icons.blur_on;
  }
}

String phaseLabel(String phase) {
  switch (phase) {
    case 'raking':
      return 'Raking';
    case 'leafBlow':
      return 'Leaf blow & bag';
    case 'seeding':
      return 'Seeding';
    case 'fertilizing':
      return 'Fertilizing';
    case 'overseeding':
      return 'Over-seeding';
    case 'aeration':
    default:
      return 'Aeration';
  }
}

/// App-wide theme. Plus Jakarta Sans, paper background, teal seed.
ThemeData redefineTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: RColors.page,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RColors.teal,
      primary: RColors.teal,
      surface: RColors.surface,
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: RColors.ink, displayColor: RColors.ink),
    splashFactory: InkRipple.splashFactory,
  );
}

/// Convenience text styles.
class RText {
  static TextStyle h1 = GoogleFonts.plusJakartaSans(
      fontSize: 24, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.5);
  static TextStyle h2 = GoogleFonts.plusJakartaSans(
      fontSize: 19, fontWeight: FontWeight.w700, color: RColors.ink);
  static TextStyle title = GoogleFonts.plusJakartaSans(
      fontSize: 14, fontWeight: FontWeight.w700, color: RColors.ink);
  static TextStyle body = GoogleFonts.plusJakartaSans(
      fontSize: 13, fontWeight: FontWeight.w500, color: RColors.ink);
  static TextStyle muted = GoogleFonts.plusJakartaSans(
      fontSize: 12, fontWeight: FontWeight.w500, color: RColors.inkMuted);
  static TextStyle eyebrow = GoogleFonts.plusJakartaSans(
      fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF888888), letterSpacing: 0.6);
  static TextStyle price = GoogleFonts.plusJakartaSans(
      fontSize: 16, fontWeight: FontWeight.w700, color: RColors.teal);
}
