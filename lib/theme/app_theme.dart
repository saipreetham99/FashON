import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Palette.
///
/// Pulled from a tailor's world rather than a UI kit: unlit dressing-room
/// plum for the ground, aged brass for anything the user acts on or reads a
/// number from, eucalyptus and clay for the two halves of a verdict. There is
/// no pure black and no pure white anywhere — every neutral carries a warm or
/// violet cast so photographed garments sit in the page instead of floating
/// on it.
abstract final class Ink0 {
  /// Page ground.
  static const ground = Color(0xFF17131C);

  /// Raised panels, nav bar.
  static const raised = Color(0xFF221C29);

  /// Cards and tiles.
  static const card = Color(0xFF2A2333);

  /// Pressed / selected fill.
  static const sunken = Color(0xFF120F17);
}

abstract final class Accent {
  /// Brass. Buttons, zips, score numerals. The one bright thing.
  static const brass = Color(0xFFE3B575);
  static const brassDim = Color(0xFF8A6B44);

  /// What is working.
  static const eucalyptus = Color(0xFF7FA9A0);

  /// What is not.
  static const clay = Color(0xFFD2766B);

  /// Mid-range warning.
  static const amber = Color(0xFFC9A227);
}

abstract final class Bone {
  static const full = Color(0xFFF2EDE6);
  static const muted = Color(0xFF9E94A8);
  static const faint = Color(0xFF6B6276);
  static const hairline = Color(0x1FF2EDE6);
}

/// Spacing scale. Multiples of 4, named so layout code reads as intent.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 48.0;
}

abstract final class Radii {
  static const tile = 14.0;
  static const card = 18.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

/// Maps a 0-10 score to its verdict colour.
///
/// Four bands, not a continuous gradient: a score is a judgement, and bands
/// make "this is fine" visibly different from "this is good" at a glance.
Color scoreColor(double score) {
  if (score >= 8.0) return Accent.eucalyptus;
  if (score >= 6.5) return Accent.brass;
  if (score >= 4.5) return Accent.amber;
  return Accent.clay;
}

/// One-word verdict for a score, used beside the numeral.
String scoreVerdict(double score) {
  if (score >= 9.0) return 'Exceptional';
  if (score >= 8.0) return 'Strong';
  if (score >= 6.5) return 'Works';
  if (score >= 4.5) return 'Forgettable';
  if (score >= 3.0) return 'Conflicts';
  return 'Wrong';
}

/// Type scale.
///
/// No font files, so personality comes from tracking and weight rather than
/// a licensed face: display sizes pull tight and negative, small labels open
/// up wide and uppercase like the print on a garment tag. Swap in
/// `google_fonts` later and only these constants change.
abstract final class Type {
  static const display = TextStyle(
    fontSize: 40,
    height: 1.0,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.4,
    color: Bone.full,
  );

  static const title = TextStyle(
    fontSize: 24,
    height: 1.15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.6,
    color: Bone.full,
  );

  static const section = TextStyle(
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: Bone.full,
  );

  static const body = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: Bone.full,
  );

  static const bodyMuted = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: Bone.muted,
  );

  static const small = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: Bone.muted,
  );

  /// Garment-tag label. Always uppercase at the call site.
  static const tag = TextStyle(
    fontSize: 11,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: Bone.muted,
  );

  /// Score numerals. Tabular so a grid of scores does not shimmer.
  static const numeral = TextStyle(
    fontSize: 30,
    height: 1.0,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.5,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Bone.full,
  );

  static const numeralSmall = TextStyle(
    fontSize: 15,
    height: 1.0,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Bone.full,
  );

  static const mono = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontFamily: 'monospace',
    color: Bone.muted,
  );
}

ThemeData buildFashonTheme() {
  const scheme = ColorScheme.dark(
    primary: Accent.brass,
    onPrimary: Ink0.sunken,
    secondary: Accent.eucalyptus,
    onSecondary: Ink0.sunken,
    surface: Ink0.card,
    onSurface: Bone.full,
    error: Accent.clay,
    onError: Ink0.sunken,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Ink0.ground,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: Type.title,
      iconTheme: IconThemeData(color: Bone.full),
    ),
    dividerTheme: const DividerThemeData(
      color: Bone.hairline,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Accent.brass,
        foregroundColor: Ink0.sunken,
        disabledBackgroundColor: Accent.brassDim,
        disabledForegroundColor: Bone.faint,
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.tile),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Accent.brass),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Bone.full,
        side: const BorderSide(color: Bone.hairline),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.tile),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ink0.card,
      hintStyle: const TextStyle(color: Bone.faint),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.tile),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.tile),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.tile),
        borderSide: const BorderSide(color: Accent.brass, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Ink0.card,
      contentTextStyle: Type.body,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.tile),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Ink0.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Ink0.raised,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: Type.section,
      contentTextStyle: Type.bodyMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Accent.brass,
      linearTrackColor: Ink0.sunken,
      circularTrackColor: Ink0.sunken,
    ),
  );
}
