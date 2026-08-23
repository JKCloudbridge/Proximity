import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/address_providers.dart';

class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Addresses')),
      body: addressesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load addresses: $e')),
        data: (addresses) {
          if (addresses.isEmpty) {
            return const Center(child: Text('No addresses yet -- add one to get started.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: addresses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final address = addresses[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
                child: ListTile(
                  leading: Icon(address.isDefault ? Icons.star : Icons.location_on_outlined, color: address.isDefault ? AppColors.accent : null),
                  title: Text(address.label?.isNotEmpty == true ? address.label! : 'Address'),
                  subtitle: Text('${address.line1}, ${address.city}, ${address.state} ${address.pincode}'),
                  trailing: address.isDefault
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await ref.read(addressRepositoryProvider).setDefault(address.id);
                            ref.invalidate(addressesProvider);
                          },
                          child: const Text('Set default'),
                        ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await context.push<bool>('/addresses/new');
          if (added == true) ref.invalidate(addressesProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
      ),
    );
  }
}
