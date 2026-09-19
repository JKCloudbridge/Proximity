import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Proximity's design system -- SPRINT_PLANNING.md §6. Deliberately not a
/// reskin of Baker Ally's maroon/gold bakery palette: a multi-category,
/// multi-shop marketplace needs to read as trustworthy neighborhood
/// infrastructure, not one warm food vertical, and needs to visually avoid
/// the red/orange/yellow territory every food-delivery incumbent already
/// owns (Zomato red, Swiggy orange, Blinkit yellow).
class AppColors {
  AppColors._();

  static const brand = Color(0xFF0F7A5C);
  static const brandDark = Color(0xFF0A5A43);
  static const brandTint = Color(0xFFE4F3EC);

  static const accent = Color(0xFFF2A73C); // marigold -- badges/ratings only, never body text
  static const urgent = Color(0xFFE4572E); // terracotta -- low-stock/errors/destructive
  static const success = Color(0xFF3FA184); // lighter tint of the brand family, not a clashing third green

  static const cream = Color(0xFFFBF7F2);
  static const ink = Color(0xFF221B1A);
  static const inkSoft = Color(0xFF7A7370);
  static const line = Color(0xFFE9E2D8);
}

/// SPRINT_PLANNING.md §6: "Plus Jakarta Sans, tabular-nums on all
/// price/quantity text." Sprint 13's design-system audit found this had
/// never actually been wired anywhere -- checked directly (grepped the
/// whole mobile codebase for `FontFeature`/`tabularFigures`, zero matches)
/// rather than assumed present because the theme file existed. The spec
/// doesn't ask for tabular-nums on every price/quantity `Text` widget
/// individually (this project has ~40 of them across ~19 files, per this
/// sprint's own audit) -- it ties the feature to the body font itself, so
/// applying it once here, to every field of the Plus Jakarta Sans
/// [TextTheme] before the four Baloo 2 display/headline overrides layer on
/// top, gets every current and future price/quantity `Text` widget for
/// free: every one of them ultimately reads a `bodyX`/`titleX`/`labelX`
/// style and `.copyWith`s onto it (fontWeight, color, ...), and `copyWith`
/// only ever overrides the fields it's actually passed -- `fontFeatures`
/// isn't one of the ~40 call sites' own `.copyWith` arguments anywhere in
/// this codebase, so it survives untouched. `TextTheme.apply()` (Flutter's
/// own built-in bulk-transform method) does NOT support `fontFeatures` --
/// checked directly against the installed SDK source
/// (`packages/flutter/lib/src/material/text_theme.dart`) before reaching
/// for a manual per-field `copyWith` here instead of assuming `.apply()`
/// could do it.
TextTheme _withTabularNums(TextTheme theme) {
  const tabularNums = [FontFeature.tabularFigures()];
  return TextTheme(
    displayLarge: theme.displayLarge?.copyWith(fontFeatures: tabularNums),
    displayMedium: theme.displayMedium?.copyWith(fontFeatures: tabularNums),
    displaySmall: theme.displaySmall?.copyWith(fontFeatures: tabularNums),
    headlineLarge: theme.headlineLarge?.copyWith(fontFeatures: tabularNums),
    headlineMedium: theme.headlineMedium?.copyWith(fontFeatures: tabularNums),
    headlineSmall: theme.headlineSmall?.copyWith(fontFeatures: tabularNums),
    titleLarge: theme.titleLarge?.copyWith(fontFeatures: tabularNums),
    titleMedium: theme.titleMedium?.copyWith(fontFeatures: tabularNums),
    titleSmall: theme.titleSmall?.copyWith(fontFeatures: tabularNums),
    bodyLarge: theme.bodyLarge?.copyWith(fontFeatures: tabularNums),
    bodyMedium: theme.bodyMedium?.copyWith(fontFeatures: tabularNums),
    bodySmall: theme.bodySmall?.copyWith(fontFeatures: tabularNums),
    labelLarge: theme.labelLarge?.copyWith(fontFeatures: tabularNums),
    labelMedium: theme.labelMedium?.copyWith(fontFeatures: tabularNums),
    labelSmall: theme.labelSmall?.copyWith(fontFeatures: tabularNums),
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final displayFont = GoogleFonts.baloo2TextTheme();
    final bodyFont = _withTabularNums(GoogleFonts.plusJakartaSansTextTheme());

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
      primary: AppColors.brand,
      surface: AppColors.cream,
      error: AppColors.urgent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.cream,
      textTheme: bodyFont.copyWith(
        // Baloo 2 for anything that reads as a headline/brand moment;
        // Plus Jakarta Sans for everything else -- same two-font
        // structural split as Baker Ally's Fredoka+Inter pairing, new
        // faces so this doesn't feel like a reskin.
        headlineLarge: displayFont.headlineLarge,
        headlineMedium: displayFont.headlineMedium,
        headlineSmall: displayFont.headlineSmall,
        titleLarge: displayFont.titleLarge,
      ),
      appBarTheme: const AppBarTheme(backgroundColor: AppColors.cream, foregroundColor: AppColors.ink, elevation: 0),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.line)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
