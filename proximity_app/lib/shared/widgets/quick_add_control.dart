import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/cart/data/models/cart_item.dart';
import '../../features/cart/presentation/providers/cart_providers.dart';

/// Shows a "+ Add" pill when [variantId] isn't in the buyer's cart yet, or a
/// "- qty +" stepper once it is. Shared across every product-card widget
/// that wants a quick-add affordance (shop-detail grid, Home's Recommended
/// row, ...) -- same guest-gate and never-throws-into-the-tile contract
/// product_detail_screen.dart's own `_addToCart` established, just reachable
/// from a card instead of only the PDP. Only ever needs the variant's id,
/// not the full `ProductVariant` shape -- both `addItem` and matching an
/// existing cart row are id-only operations, so this stays reusable even for
/// feeds (like `GET /v1/recommended`) that don't return a full variant.
class QuickAddControl extends ConsumerWidget {
  const QuickAddControl({super.key, required this.variantId});

  final String variantId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final isLoggedIn = ref.read(authProvider).isLoggedIn;
    if (!isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sign in to add items to your cart'),
          action: SnackBarAction(label: 'Sign in', onPressed: () => context.push('/login')),
        ),
      );
      return;
    }
    await ref.read(cartRepositoryProvider).addItem(variantId);
    ref.invalidate(cartProvider);
  }

  Future<void> _setQuantity(WidgetRef ref, String cartItemId, int quantity) async {
    if (quantity <= 0) {
      await ref.read(cartRepositoryProvider).removeItem(cartItemId);
    } else {
      await ref.read(cartRepositoryProvider).updateQuantity(cartItemId, quantity);
    }
    ref.invalidate(cartProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider).value ?? const <CartItem>[];
    CartItem? existing;
    for (final item in cartItems) {
      if (item.variant.id == variantId) {
        existing = item;
        break;
      }
    }

    if (existing == null) {
      return _Pill(
        child: InkWell(
          onTap: () => _add(context, ref),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text('+ Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
      );
    }

    final item = existing;
    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(icon: Icons.remove, onTap: () => _setQuantity(ref, item.id, item.quantity - 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('${item.quantity}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          _StepperButton(icon: Icons.add, onTap: () => _setQuantity(ref, item.id, item.quantity + 1)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}
