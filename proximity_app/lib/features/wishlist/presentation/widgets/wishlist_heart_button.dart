import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../providers/wishlist_providers.dart';

/// The one wishlist toggle every surface that shows a product (shop-detail
/// grid tile, PDP header) reuses, rather than each screen re-implementing
/// its own add/remove-and-refetch logic.
///
/// Guests can browse shop/product detail (app_router.dart's
/// `_protectedPaths` doesn't gate either) but wishlists are own-user data
/// (§5.2) with no guest-usable backing -- routes/wishlist.ts's whole
/// `/wishlist*` group requires a signed-in buyer. So an unauthenticated tap
/// never calls the API at all; it prompts sign-in instead, same "gated at
/// the specific action, not at the door" rule app_router.dart's own header
/// comment already states for this app.
class WishlistHeartButton extends ConsumerWidget {
  const WishlistHeartButton({super.key, required this.productId, this.size = 22});

  final String productId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final savedIdsAsync = ref.watch(wishlistProductIdsProvider);
    final saved = auth.isLoggedIn && (savedIdsAsync.value?.contains(productId) ?? false);

    return IconButton(
      icon: Icon(saved ? Icons.favorite : Icons.favorite_border, color: saved ? AppColors.urgent : AppColors.inkSoft, size: size),
      onPressed: () => _handleTap(context, ref, auth.isLoggedIn, saved),
      tooltip: saved ? 'Remove from wishlist' : 'Add to wishlist',
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref, bool isLoggedIn, bool saved) async {
    if (!isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sign in to save items to your wishlist'),
          action: SnackBarAction(label: 'Sign in', onPressed: () => context.push('/login')),
        ),
      );
      return;
    }

    final repository = ref.read(wishlistRepositoryProvider);
    // Fire-and-refresh, not optimistic -- a wishlist toggle is infrequent
    // and low-stakes enough that waiting for the real round trip before
    // flipping the icon (via wishlistProvider's own invalidate-triggered
    // refetch) is simpler than reconciling an optimistic guess against a
    // failed request.
    if (saved) {
      await repository.remove(productId);
    } else {
      await repository.add(productId);
    }
    ref.invalidate(wishlistProvider);
  }
}
