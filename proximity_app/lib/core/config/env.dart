import 'package:envied/envied.dart';

part 'env.g.dart';

/// Build-time config from `.env` -- same envied pattern as Baker Ally's
/// core/config/env.dart. Only client-safe values belong here: the anon key
/// is meant to be public (Supabase's RLS/service-role boundary protects
/// data, not this key -- see SPRINT_PLANNING.md §5.1 for what actually does).
@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'SUPABASE_URL')
  static const String supabaseUrl = _Env.supabaseUrl;

  @EnviedField(varName: 'SUPABASE_ANON_KEY')
  static const String supabaseAnonKey = _Env.supabaseAnonKey;

  @EnviedField(varName: 'API_BASE_URL')
  static const String apiBaseUrl = _Env.apiBaseUrl;

  @EnviedField(varName: 'GOOGLE_IOS_CLIENT_ID')
  static const String googleIosClientId = _Env.googleIosClientId;

  @EnviedField(varName: 'GOOGLE_SERVER_CLIENT_ID')
  static const String googleServerClientId = _Env.googleServerClientId;

  @EnviedField(varName: 'APPLE_SERVICE_ID')
  static const String appleServiceId = _Env.appleServiceId;

  @EnviedField(varName: 'APPLE_REDIRECT_URI')
  static const String appleRedirectUri = _Env.appleRedirectUri;

  // Sprint 11 -- all five are client-safe (same "public half of a key pair"
  // shape as supabaseAnonKey above), fed straight into
  // Firebase.initializeApp(options: FirebaseOptions(...)) by
  // push_service.dart. Required (not `optional: true`), matching every
  // other field in this class -- same "unset means empty string, not a
  // missing key" shape GOOGLE_IOS_CLIENT_ID etc. already have, since no
  // real Firebase project exists yet.
  @EnviedField(varName: 'FIREBASE_API_KEY')
  static const String firebaseApiKey = _Env.firebaseApiKey;

  @EnviedField(varName: 'FIREBASE_PROJECT_ID')
  static const String firebaseProjectId = _Env.firebaseProjectId;

  @EnviedField(varName: 'FIREBASE_MESSAGING_SENDER_ID')
  static const String firebaseMessagingSenderId = _Env.firebaseMessagingSenderId;

  @EnviedField(varName: 'FIREBASE_APP_ID_ANDROID')
  static const String firebaseAppIdAndroid = _Env.firebaseAppIdAndroid;

  @EnviedField(varName: 'FIREBASE_APP_ID_IOS')
  static const String firebaseAppIdIos = _Env.firebaseAppIdIos;
}
