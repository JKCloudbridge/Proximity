import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../data/models/rider_profile.dart';
import '../providers/rider_providers.dart';
import 'rider_home_screen.dart';

/// §8.5's "lightweight in-app view" rider touchpoint. Sprint 2 built
/// signup + KYC upload -> is_verified=false -> wait for admin; Sprint 9
/// adds the actual working-rider experience (RiderHomeScreen) once
/// `profile.isVerified` -- this screen still owns the branch between "not
/// verified yet" and "verified," it just hands off to a real screen for the
/// second case now instead of a static placeholder.
///
/// One screen, not two -- whether the caller sees the form or the status
/// card is decided by whether `myRiderProfileProvider` already has data,
/// same "single screen branches on data presence" shape as most of this
/// sprint's onboarding flows.
class RiderOnboardingScreen extends ConsumerWidget {
  const RiderOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myRiderProfileProvider);
    // riverpod 3.x's AsyncValue.value is a plain nullable getter (the old
    // valueOrNull), checked against the actually-installed 3.4.2 source.
    final title = profileAsync.value?.isVerified == true ? 'Deliveries' : 'Become a rider';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Could not load your rider status: $err')),
        data: (profile) => profile == null
            ? const _RiderOnboardingForm()
            : profile.isVerified
                ? RiderHomeScreen(profile: profile)
                : _RiderStatusCard(profile: profile),
      ),
    );
  }
}

class _RiderStatusCard extends ConsumerWidget {
  const _RiderStatusCard({required this.profile});

  final RiderProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            profile.isVerified ? Icons.verified : Icons.hourglass_top,
            size: 56,
            color: profile.isVerified ? AppColors.brand : AppColors.accent,
          ),
          const SizedBox(height: 16),
          Text(
            profile.isVerified ? "You're an approved rider" : 'Application pending review',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            profile.isVerified
                ? 'Delivery assignments and the online/offline toggle land in a later update.'
                : 'An admin needs to review your KYC document before you can start accepting deliveries.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => _showEditSheet(context, ref, profile),
            child: const Text('Edit details / resubmit document'),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, RiderProfile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _RiderOnboardingForm(existing: profile)),
    );
  }
}

class _RiderOnboardingForm extends ConsumerStatefulWidget {
  const _RiderOnboardingForm({this.existing});

  final RiderProfile? existing;

  @override
  ConsumerState<_RiderOnboardingForm> createState() => _RiderOnboardingFormState();
}

class _RiderOnboardingFormState extends ConsumerState<_RiderOnboardingForm> {
  late final _nameController = TextEditingController(text: widget.existing?.fullName ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late final _vehicleNumberController = TextEditingController(text: widget.existing?.vehicleNumber ?? '');
  String? _vehicleType;

  XFile? _pickedDocument;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _vehicleType = widget.existing?.vehicleType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final file = await ref.read(riderDocumentServiceProvider).pickDocumentFromGallery();
    if (file != null) setState(() => _pickedDocument = file);
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Name and phone are required');
      return;
    }
    // A first-time submission needs a KYC document; a resubmit can skip
    // re-uploading if nothing changed (migrations/015's RPC keeps the
    // existing kyc_document_url when none is posted).
    if (widget.existing == null && _pickedDocument == null) {
      setState(() => _error = 'Please add a photo of your ID/driving license');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final userId = ref.read(authProvider).userId;
      String? documentPath;
      if (_pickedDocument != null && userId != null) {
        documentPath = await ref.read(riderDocumentServiceProvider).uploadDocument(userId, _pickedDocument!);
      }

      await ref.read(riderRepositoryProvider).createOrUpdateProfile(
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            vehicleType: _vehicleType,
            vehicleNumber: _vehicleNumberController.text.trim().isEmpty ? null : _vehicleNumberController.text.trim(),
            kycDocumentPath: documentPath,
          );

      ref.invalidate(myRiderProfileProvider);
      if (mounted && widget.existing != null) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell us about yourself and your vehicle. An admin reviews every application before you can start delivering.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _vehicleType,
            decoration: const InputDecoration(labelText: 'Vehicle type'),
            items: const [
              DropdownMenuItem(value: 'bike', child: Text('Motorbike')),
              DropdownMenuItem(value: 'scooter', child: Text('Scooter')),
              DropdownMenuItem(value: 'bicycle', child: Text('Bicycle')),
              DropdownMenuItem(value: 'on_foot', child: Text('On foot')),
            ],
            onChanged: (value) => setState(() => _vehicleType = value),
          ),
          const SizedBox(height: 12),
          TextField(controller: _vehicleNumberController, decoration: const InputDecoration(labelText: 'Vehicle number (optional)')),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickDocument,
            icon: const Icon(Icons.upload_file),
            label: Text(_pickedDocument != null ? 'Document selected: ${_pickedDocument!.name}' : 'Upload ID / driving license photo'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.existing == null ? 'Submit application' : 'Save changes'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.urgent))),
        ],
      ),
    );
  }
}
