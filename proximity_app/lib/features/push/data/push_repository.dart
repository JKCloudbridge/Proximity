import 'package:dio/dio.dart';

/// Mirrors `POST/DELETE /v1/push/token` (routes/push.ts, Sprint 11).
class PushRepository {
  PushRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<void> registerToken(String fcmToken) async {
    await _dio.post<void>('/v1/push/token', data: {'fcmToken': fcmToken});
  }

  Future<void> unregisterToken() async {
    await _dio.delete<void>('/v1/push/token');
  }
}
