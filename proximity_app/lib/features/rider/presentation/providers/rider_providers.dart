import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/rider_document_service.dart';
import '../../data/rider_repository.dart';
import '../../data/models/rider_profile.dart';

final riderRepositoryProvider = Provider<RiderRepository>((ref) {
  return RiderRepository(dio: ref.watch(dioProvider));
});

final riderDocumentServiceProvider = Provider<RiderDocumentService>((ref) {
  return RiderDocumentService(supabase: ref.watch(supabaseClientProvider));
});

/// Network-only, same "no Drift caching yet" call as addressesProvider --
/// re-fetched via ref.invalidate after a successful submit.
final myRiderProfileProvider = FutureProvider<RiderProfile?>((ref) {
  return ref.watch(riderRepositoryProvider).getMyProfile();
});
