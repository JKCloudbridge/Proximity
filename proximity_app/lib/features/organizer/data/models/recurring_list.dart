/// Sprint 11 -- mirrors `GET/POST /v1/recurring-lists*` (routes/
/// recurringLists.ts, backend; migrations/043's own header has the full
/// schema-design reasoning). `cadence` stays a bare String (not an enum) at
/// this layer, same "server is the source of truth for the allowed set"
/// convention `OrderGroupSummary.overallStatus` already established in
/// Sprint 10 -- `RecurringListCadence` (below) is a presentation-only
/// helper, not a parse-time constraint.
class RecurringList {
  const RecurringList({
    required this.id,
    required this.name,
    required this.cadence,
    this.intervalDays,
    required this.timeOfDay,
    required this.nextRunAt,
    this.lastRunAt,
    required this.isActive,
    this.itemCount,
    this.items,
  });

  final String id;
  final String name;
  final String cadence; // 'daily' | 'weekly' | 'biweekly' | 'monthly' | 'custom_days'
  final int? intervalDays;
  final String timeOfDay; // "HH:mm:ss", IST wall-clock (backend convention, lib/slots.ts)
  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final bool isActive;
  /// Present on the list endpoint (a cheap COUNT, routes/recurringLists.ts),
  /// absent on the detail endpoint, which sends `items` (below) instead --
  /// the screen that needs one never needs the other.
  final int? itemCount;
  final List<RecurringListItem>? items;

  factory RecurringList.fromJson(Map<String, dynamic> json) {
    return RecurringList(
      id: json['id'] as String,
      name: json['name'] as String,
      cadence: json['cadence'] as String,
      intervalDays: json['intervalDays'] as int?,
      timeOfDay: json['timeOfDay'] as String,
      nextRunAt: DateTime.parse(json['nextRunAt'] as String),
      lastRunAt: json['lastRunAt'] != null ? DateTime.parse(json['lastRunAt'] as String) : null,
      isActive: json['isActive'] as bool,
      itemCount: json['itemCount'] as int?,
      items: json['items'] != null
          ? (json['items'] as List<dynamic>).map((e) => RecurringListItem.fromJson(e as Map<String, dynamic>)).toList()
          : null,
    );
  }
}

class RecurringListItem {
  const RecurringListItem({
    required this.id,
    required this.variantId,
    required this.quantity,
    required this.isAvailable,
    this.productName,
    this.productImageUrl,
    this.isVeg,
    this.unitValue,
    this.unitLabel,
    this.price,
  });

  final String id;
  final String variantId;
  final int quantity;
  final bool isAvailable;
  final String? productName;
  final String? productImageUrl;
  final bool? isVeg;
  final String? unitValue;
  final String? unitLabel;
  final int? price;

  factory RecurringListItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final variant = json['variant'] as Map<String, dynamic>?;
    return RecurringListItem(
      id: json['id'] as String,
      variantId: json['variantId'] as String,
      quantity: json['quantity'] as int,
      isAvailable: json['isAvailable'] as bool,
      productName: product?['name'] as String?,
      productImageUrl: product?['imageUrl'] as String?,
      isVeg: product?['isVeg'] as bool?,
      unitValue: variant?['unitValue'] as String?,
      unitLabel: variant?['unitLabel'] as String?,
      price: variant?['price'] as int?,
    );
  }
}

/// Presentation-only cadence metadata -- label text and which extra input
/// (interval-days) a form needs to show. Kept separate from the bare
/// `cadence` string on the model itself, same "server/wire shape vs. UI
/// helper" split `formatPaise`/currency.dart already draws elsewhere.
enum RecurringListCadence {
  daily('daily', 'Daily'),
  weekly('weekly', 'Weekly'),
  biweekly('biweekly', 'Every 2 weeks'),
  monthly('monthly', 'Monthly'),
  customDays('custom_days', 'Custom');

  const RecurringListCadence(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static RecurringListCadence fromWireValue(String value) {
    return RecurringListCadence.values.firstWhere((c) => c.wireValue == value, orElse: () => RecurringListCadence.weekly);
  }
}
