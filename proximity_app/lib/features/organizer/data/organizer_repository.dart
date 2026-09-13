import 'package:dio/dio.dart';

import 'models/recurring_list.dart';

/// Mirrors `/v1/recurring-lists*` (routes/recurringLists.ts, Sprint 11).
class OrganizerRepository {
  OrganizerRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<RecurringList>> getLists() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/recurring-lists');
    return (response.data!['data'] as List<dynamic>)
        .map((e) => RecurringList.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RecurringList> getList(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/recurring-lists/$id');
    return RecurringList.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  Future<RecurringList> createList({
    required String name,
    required String cadence,
    int? intervalDays,
    required String timeOfDay,
    required List<({String variantId, int quantity})> items,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/recurring-lists',
      data: {
        'name': name,
        'cadence': cadence,
        if (intervalDays != null) 'intervalDays': intervalDays,
        'timeOfDay': timeOfDay,
        'items': items.map((i) => {'variantId': i.variantId, 'quantity': i.quantity}).toList(),
      },
    );
    return RecurringList.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  Future<RecurringList> updateSchedule(
    String id, {
    String? name,
    String? cadence,
    int? intervalDays,
    String? timeOfDay,
    bool? isActive,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/v1/recurring-lists/$id',
      data: {
        if (name != null) 'name': name,
        if (cadence != null) 'cadence': cadence,
        if (intervalDays != null) 'intervalDays': intervalDays,
        if (timeOfDay != null) 'timeOfDay': timeOfDay,
        if (isActive != null) 'isActive': isActive,
      },
    );
    return RecurringList.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  Future<List<RecurringListItem>> replaceItems(String id, List<({String variantId, int quantity})> items) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/v1/recurring-lists/$id/items',
      data: {'items': items.map((i) => {'variantId': i.variantId, 'quantity': i.quantity}).toList()},
    );
    return ((response.data!['data'] as Map<String, dynamic>)['items'] as List<dynamic>)
        .map((e) => RecurringListItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteList(String id) async {
    await _dio.delete<void>('/v1/recurring-lists/$id');
  }
}
