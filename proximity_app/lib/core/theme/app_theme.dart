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

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final displayFont = GoogleFonts.baloo2TextTheme();
    final bodyFont = GoogleFonts.plusJakartaSansTextTheme();

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
