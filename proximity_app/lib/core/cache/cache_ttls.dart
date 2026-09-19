/// Sprint 15.md's TTL philosophy: "correctness over speed, speed only
/// where it's actually safe" -- short, conservative durations, reasoned per
/// collection against how often its underlying data actually changes, not
/// tuned for maximum cache-hit rate. Shop/product listings get the
/// shortest TTLs here because `stock_status`/price are the most
/// correctness-sensitive fields this sprint's scope ever shows from a
/// cache (a stale "in stock" is the closest thing on this list to the
/// "stale cart total" class of bug the sprint doc explicitly excludes
/// elsewhere); the admin-curated, rarely-changing category list gets the
/// longest.
class CacheTtls {
  CacheTtls._();

  static const categories = Duration(minutes: 20);
  static const nearbyShops = Duration(minutes: 5);
  static const recommendedProducts = Duration(minutes: 5);
  static const frequentlyBought = Duration(minutes: 10);
  static const shopDetail = Duration(minutes: 5);
  static const shopSubCategories = Duration(minutes: 10);
  static const shopProducts = Duration(minutes: 3);
  static const productDetail = Duration(minutes: 3);
}
