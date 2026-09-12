import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// KYC document upload goes Flutter -> Supabase Storage directly, not
/// proxied through the Edge Function -- same precedent as Baker Ally's
/// avatar upload (baker_ally_flutter/.../user_repository.dart) and spelled
/// out in migrations/011's comment: Storage has its own auth surface
/// backed by the caller's real JWT (unlike proximity_backend's own DB
/// connection, which is the service-role pooler connection with no
/// populated auth.uid() -- see lib/db.ts), so this is a legitimately
/// different, already-authenticated path, not a second weaker copy of the
/// §5.1 trust boundary.
///
/// Object path is `{user_id}/{filename}` -- migrations/016's RLS policies
/// (`(storage.foldername(name))[1] = auth.uid()::text`) only allow a rider
/// to read/write their own folder, so this exact shape is load-bearing,
/// not a style choice.
class RiderDocumentService {
  RiderDocumentService({required SupabaseClient supabase}) : _supabase = supabase;

  final SupabaseClient _supabase;

  static const _bucket = 'rider-documents';

  Future<XFile?> pickDocumentImage() {
    return ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
  }

  Future<XFile?> pickDocumentFromGallery() {
    return ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
  }

  /// Returns the storage *path* (not a public URL -- the bucket is private,
  /// see migrations/016) to hand to RiderRepository.createOrUpdateProfile.
  Future<String> uploadDocument(String userId, XFile file) async {
    final bytes = await file.readAsBytes();
    final extension = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final path = '$userId/kyc_${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    return path;
  }
}
