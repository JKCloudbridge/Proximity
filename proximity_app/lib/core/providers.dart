import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache/app_database.dart';
import 'cache/local_cache.dart';
import 'network/dio_client.dart';
import 'storage/secure_storage.dart';

/// Root providers -- alive for the app's lifetime, same role as Baker
/// Ally's core/providers.dart. Feature root providers (authProvider,
/// addressesProvider, ...) live in their own feature folders and build on
/// these.

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage();
});

final dioProvider = Provider<Dio>((ref) {
  return buildDioClient(ref.watch(secureStorageProvider));
});

/// Sprint 15 -- one Drift database, alive for the app's lifetime (same as
/// every other provider on this page), opened lazily on first read rather
/// than eagerly in main.dart -- nothing in this app needs the cache to be
/// warm before the first frame, only before the first cached provider is
/// actually read.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final localCacheProvider = Provider<LocalCache>((ref) {
  return LocalCache(ref.watch(appDatabaseProvider));
});
