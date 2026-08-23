import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/location_service.dart' show LocationPermissionResult;
import '../../data/models/address.dart';
import '../providers/address_providers.dart';

/// "Use my current location" (GPS + reverse-geocode to pre-fill) or manual
/// entry (forward-geocoded on submit) -- both paths funnel into the same
/// lat/lng-required create call, since `addresses.location` is NOT NULL
/// (migrations/002) and every downstream feature (shops-near-you, delivery
/// fee, fulfillment slots) depends on it existing.
class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key});

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _labelController = TextEditingController();
  final _line1Controller = TextEditingController();
  final _line2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  double? _lat;
  double? _lng;
  bool _resolvingLocation = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    _line1Controller.dispose();
    _line2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _resolvingLocation = true;
      _error = null;
    });
    final locationService = ref.read(locationServiceProvider);
    try {
      final permission = await locationService.ensurePermission();
      if (permission != LocationPermissionResult.granted) {
        setState(() => _error = 'Location permission not granted (${permission.name})');
        return;
      }
      final position = await locationService.getCurrentPosition();
      final placemark = await locationService.placemarkFromPosition(lat: position.lat, lng: position.lng);
      setState(() {
        _lat = position.lat;
        _lng = position.lng;
        if (placemark != null) {
          _line1Controller.text = [placemark.thoroughfare, placemark.subThoroughfare].where((s) => s?.isNotEmpty == true).join(', ');
          _cityController.text = placemark.locality ?? '';
          _stateController.text = placemark.administrativeArea ?? '';
          _pincodeController.text = placemark.postalCode ?? '';
        }
      });
    } catch (e) {
      setState(() => _error = 'Could not get current location: $e');
    } finally {
      if (mounted) setState(() => _resolvingLocation = false);
    }
  }

  Future<void> _save() async {
    if (_line1Controller.text.trim().isEmpty ||
        _cityController.text.trim().isEmpty ||
        _stateController.text.trim().isEmpty ||
        _pincodeController.text.trim().isEmpty) {
      setState(() => _error = 'Fill in address, city, state, and pincode');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      double lat;
      double lng;
      if (_lat != null && _lng != null) {
        lat = _lat!;
        lng = _lng!;
      } else {
        // Manual entry with no GPS pin -- forward-geocode the typed address
        // instead of blocking save on "use current location" specifically.
        final fullAddress = '${_line1Controller.text}, ${_cityController.text}, ${_stateController.text} ${_pincodeController.text}';
        final resolved = await ref.read(locationServiceProvider).coordinatesFromAddress(fullAddress);
        if (resolved == null) {
          setState(() => _error = "Couldn't resolve this address to a location -- check it and try again, or use \"Use current location\" instead.");
          return;
        }
        lat = resolved.lat;
        lng = resolved.lng;
      }

      await ref.read(addressRepositoryProvider).createAddress(
            Address(
              id: '',
              label: _labelController.text.trim().isEmpty ? null : _labelController.text.trim(),
              line1: _line1Controller.text.trim(),
              line2: _line2Controller.text.trim().isEmpty ? null : _line2Controller.text.trim(),
              city: _cityController.text.trim(),
              state: _stateController.text.trim(),
              pincode: _pincodeController.text.trim(),
              lat: lat,
              lng: lng,
              isDefault: false,
            ),
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not save address: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _resolvingLocation || _saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Add address')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _useCurrentLocation,
              icon: _resolvingLocation
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: const Text('Use current location'),
            ),
            if (_lat != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Pinned: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}', style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 16),
            TextField(controller: _labelController, decoration: const InputDecoration(labelText: 'Label (Home, Work...)')),
            const SizedBox(height: 12),
            TextField(controller: _line1Controller, decoration: const InputDecoration(labelText: 'Address line 1')),
            const SizedBox(height: 12),
            TextField(controller: _line2Controller, decoration: const InputDecoration(labelText: 'Address line 2 (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _cityController, decoration: const InputDecoration(labelText: 'City')),
            const SizedBox(height: 12),
            TextField(controller: _stateController, decoration: const InputDecoration(labelText: 'State')),
            const SizedBox(height: 12),
            TextField(controller: _pincodeController, decoration: const InputDecoration(labelText: 'Pincode'), keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: busy ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save address'),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
