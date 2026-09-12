/// Every price in this backend is a paise integer (SPRINT_PLANNING.md
/// §1.7's "paise-integer money" convention) -- this sprint is mobile's first
/// screen that actually renders one, so the rupee-string formatting lives
/// here once rather than being re-derived at each of the three call sites
/// that need it (shop-detail grid, PDP variant selector, wishlist grid).
/// Whole-rupee prices (the overwhelming majority, since kirana pricing is
/// rarely sub-rupee) print with no decimals; anything with real paise still
/// shows them rather than silently rounding away real money.
String formatPaise(int paise) {
  final rupees = paise / 100;
  return rupees == rupees.roundToDouble() ? '₹${rupees.toStringAsFixed(0)}' : '₹${rupees.toStringAsFixed(2)}';
}
