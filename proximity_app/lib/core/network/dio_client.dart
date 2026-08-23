import 'package:dio/dio.dart';

import '../config/env.dart';
import '../storage/secure_storage.dart';

/// Every request to proximity_backend goes through this client. All
/// business data (profile, addresses, and everything added in later
/// sprints) flows Dio -> Hono, never directly through supabase_flutter --
/// see SPRINT_PLANNING.md §5.1 for why that's a hard rule here, not just a
/// style preference: the backend's own DB connection is service-role and
/// bypasses RLS, so the Edge Function's authMiddleware is the one and only
/// trust boundary. A second data path straight from Flutter to PostgREST
/// would be a second, weaker boundary sitting next to it.
Dio buildDioClient(SecureStorage secureStorage) {
  final dio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final jwt = await secureStorage.readJwt();
        if (jwt != null) {
          options.headers['Authorization'] = 'Bearer $jwt';
        }
        handler.next(options);
      },
    ),
  );

  return dio;
}
