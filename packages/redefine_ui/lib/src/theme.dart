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
  static const danger = Color(0xFF8A2E2E);
  static const dangerTint = Color(0xFFFBEAEA);
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

/// Icon for a plough request, with or without shovelling.
IconData serviceIcon({required bool shovel}) => Icons.ac_unit_rounded;

String serviceLabel({required bool shovel}) => shovel ? 'Plough + shovel' : 'Plough';

/// The property illustration keys the API accepts, in picker order.
const List<String> kIllustrations = [
  'house',
  'bungalow',
  'townhouse',
  'cabin',
  'duplex',
  'farmhouse',
  'cottage',
  'apartment',
  'garage',
];

/// Icon for a property illustration key; unknown keys fall back to `house`.
IconData illustrationIcon(String key) => switch (key) {
  'bungalow' => Icons.bungalow_rounded,
  'townhouse' => Icons.holiday_village_rounded,
  'cabin' => Icons.cabin_rounded,
  'duplex' => Icons.maps_home_work_rounded,
  'farmhouse' => Icons.gite_rounded,
  'cottage' => Icons.cottage_rounded,
  'apartment' => Icons.apartment_rounded,
  'garage' => Icons.garage_rounded,
  _ => Icons.house_rounded,
};

Color illustrationColor(String key) => switch (key) {
  'bungalow' || 'duplex' => RColors.tealDeep,
  'townhouse' || 'cabin' || 'apartment' => RColors.slate,
  'farmhouse' || 'cottage' => RColors.amber,
  'garage' => RColors.inkMuted,
  _ => RColors.teal,
};

/// App-wide theme. Plus Jakarta Sans, paper background, teal seed.
ThemeData redefineTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: RColors.page,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RColors.teal,
      primary: RColors.teal,
      surface: RColors.surface,
      error: RColors.danger,
    ),
  );
  final menuText = GoogleFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: RColors.ink,
  );
  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: RColors.ink, displayColor: RColors.ink),
    splashFactory: InkRipple.splashFactory,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: RColors.teal,
      linearTrackColor: RColors.tealTint,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: RColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: RColors.white,
      surfaceTintColor: Colors.transparent,
      textStyle: menuText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: RColors.border, width: 0.6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RColors.ink,
      contentTextStyle: menuText.copyWith(color: RColors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Convenience text styles.
class RText {
  static final TextStyle h1 = GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: RColors.ink,
    letterSpacing: -0.5,
  );
  static final TextStyle h2 = GoogleFonts.plusJakartaSans(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: RColors.ink,
  );
  static final TextStyle title = GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: RColors.ink,
  );
  static final TextStyle body = GoogleFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: RColors.ink,
  );
  static final TextStyle muted = GoogleFonts.plusJakartaSans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: RColors.inkMuted,
  );
  static final TextStyle eyebrow = GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF888888),
    letterSpacing: 0.6,
  );
  static final TextStyle price = GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: RColors.teal,
  );
}
