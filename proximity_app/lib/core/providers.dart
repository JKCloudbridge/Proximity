import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'network/dio_client.dart';
import 'storage/secure_storage.dart';

/// Root providers -- alive for the app's lifetime, same role as Baker
/// Ally's core/providers.dart. Feature root providers (authProvider,
/// addressesProvider, ...) live in their own feature folders and build on
/// these. No Drift/local-db provider yet -- Sprint 1 has nothing that needs
/// offline caching (that starts with Home in Sprint 4 and Cart in Sprint 6).

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage();
});

final dioProvider = Provider<Dio>((ref) {
  return buildDioClient(ref.watch(secureStorageProvider));
});
