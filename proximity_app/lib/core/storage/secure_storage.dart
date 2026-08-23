import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted on-device storage for the session JWT (Keychain on iOS,
/// EncryptedSharedPreferences/Keystore on Android). Dio's auth interceptor
/// reads from here rather than from supabase_flutter's in-memory session --
/// identical rationale and shape to Baker Ally's SecureStorage.
class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _jwtKey = 'session_jwt';

  Future<void> writeJwt(String jwt) => _storage.write(key: _jwtKey, value: jwt);

  Future<String?> readJwt() => _storage.read(key: _jwtKey);

  Future<void> clearJwt() => _storage.delete(key: _jwtKey);
}
