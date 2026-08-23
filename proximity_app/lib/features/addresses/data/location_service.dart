import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Resolves a lat/lng from either the device's GPS ("use my current
/// location") or on-device OS geocoding for a typed address -- no Google
/// Maps/Places API key needed for either path (SPRINT_PLANNING.md §3.2
/// notes Maps/Geocoding billing as a later, separate account; this is the
/// zero-setup interim path, not a permanent substitute for Places
/// Autocomplete's better address-matching once that account exists). This
/// is the one seam to swap when that happens -- callers depend on this
/// class, not on `geocoding`/`geolocator` directly.
class LocationService {
  LocationService() : _geocoding = Geocoding();

  final Geocoding _geocoding;

  /// Throws [LocationServiceDisabledException] or a [PermissionDeniedError]-
  /// shaped state via the return value -- callers should check
  /// [LocationPermissionResult] before calling [getCurrentPosition].
  Future<LocationPermissionResult> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionResult.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) return LocationPermissionResult.denied;
    if (permission == LocationPermission.deniedForever) return LocationPermissionResult.deniedForever;
    return LocationPermissionResult.granted;
  }

  Future<({double lat, double lng})> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return (lat: position.latitude, lng: position.longitude);
  }

  /// Reverse-geocodes a lat/lng into a human-readable address, to pre-fill
  /// the address form after "use my current location".
  Future<Placemark?> placemarkFromPosition({required double lat, required double lng}) async {
    final results = await _geocoding.placemarkFromCoordinates(lat, lng);
    return results.isNotEmpty ? results.first : null;
  }

  /// Forward-geocodes a typed address into a lat/lng, for the manual-entry
  /// path (no GPS/permission involved).
  Future<({double lat, double lng})?> coordinatesFromAddress(String address) async {
    final results = await _geocoding.locationFromAddress(address);
    if (results.isEmpty) return null;
    return (lat: results.first.latitude, lng: results.first.longitude);
  }
}

enum LocationPermissionResult { granted, denied, deniedForever, serviceDisabled }
