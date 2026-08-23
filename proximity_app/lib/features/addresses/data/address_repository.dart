import 'package:dio/dio.dart';

import 'models/address.dart';

class AddressRepository {
  AddressRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<Address>> getAddresses() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/addresses');
    return (response.data!['data'] as List).map((e) => Address.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Address> createAddress(Address address) async {
    final response = await _dio.post<Map<String, dynamic>>('/v1/addresses', data: address.toCreateJson());
    return Address.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  /// Routed through the server's rpc_set_default_address (see
  /// proximity_backend/.../routes/addresses.ts's `POST /addresses/:id/default`)
  /// rather than a PATCH with `isDefault: true` -- that endpoint is
  /// specifically the one with the atomic-flip guarantee
  /// SPRINT_PLANNING.md §5 exists to enforce.
  Future<void> setDefault(String addressId) async {
    await _dio.post<Map<String, dynamic>>('/v1/addresses/$addressId/default');
  }

  Future<void> deleteAddress(String addressId) async {
    await _dio.delete<Map<String, dynamic>>('/v1/addresses/$addressId');
  }
}
