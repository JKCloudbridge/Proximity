import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Sprint 15's local caching layer (Sprint planning/Sprint 15.md) -- one
/// generic key/payload/fetchedAt table rather than a separate normalized
/// Drift table per cached entity (Category, NearbyShop, ShopProduct, ...).
/// Every cached provider (home_providers.dart, shop_detail_providers.dart,
/// product_detail_providers.dart) already has its own typed Dart model with
/// `fromJson`/`toJson`; what they all need from local storage is the exact
/// same thing -- "give me the JSON I last wrote under this key, and tell me
/// when I wrote it" -- so that's the one thing this table does. The
/// freshness check itself (`WHERE cache_key = ?`, read in Dart against the
/// TTL) is still a real, typed, compile-time-checked Drift query, which is
/// the concrete value §Sprint 15.md names for choosing Drift here; a fully
/// normalized schema would mean eight near-identical table+DAO pairs for
/// read-only, server-is-the-source-of-truth copies of data this sprint's own
/// scope calls "targeted, not full offline-first."
class CacheEntries extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

@DriftDatabase(tables: [CacheEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<CacheEntry?> readEntry(String key) {
    return (select(cacheEntries)..where((t) => t.cacheKey.equals(key))).getSingleOrNull();
  }

  Future<void> writeEntry(String key, String jsonPayload) {
    return into(cacheEntries).insertOnConflictUpdate(
      CacheEntriesCompanion.insert(cacheKey: key, payload: jsonPayload, fetchedAt: DateTime.now()),
    );
  }
}

// `driftDatabase(native: DriftNativeOptions(databaseDirectory:
// getApplicationSupportDirectory))` is drift_flutter's own current
// documented setup (drift.simonbinder.eu/setup, checked live before writing
// this) -- it resolves a real per-app storage directory itself and works
// around sqlite3's own "wants /tmp, which Android forbids" landmine, so
// there's no manual NativeDatabase/path-joining to get wrong here.
QueryExecutor _openConnection() {
  return driftDatabase(name: 'proximity_cache', native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory));
}
