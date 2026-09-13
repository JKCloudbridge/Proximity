/// Sprint 10 -- mirrors `GET /v1/order-again/frequently-bought`'s entries
/// (lib/frequentlyBoughtGroups.ts, backend) -- see that file's header for
/// what "a group" means in this project's own multi-shop order model (one
/// shop's `orders` row's item-set, not one `order_groups` row).
class FrequentlyBoughtGroup {
  const FrequentlyBoughtGroup({
    required this.groupKey,
    required this.source,
    required this.timesOrdered,
    required this.lastOrderedAt,
    required this.shopId,
    required this.shopName,
    required this.items,
    required this.totalPrice,
    required this.anyUnavailable,
  });

  final String groupKey;
  final String source; // 'mine' | 'platform'
  final int timesOrdered;
  final DateTime lastOrderedAt;
  final String shopId;
  final String shopName;
  final List<FrequentlyBoughtGroupItem> items;
  final int totalPrice;
  final bool anyUnavailable;

  bool get isMine => source == 'mine';

  factory FrequentlyBoughtGroup.fromJson(Map<String, dynamic> json) {
    return FrequentlyBoughtGroup(
      groupKey: json['groupKey'] as String,
      source: json['source'] as String,
      timesOrdered: json['timesOrdered'] as int,
      lastOrderedAt: DateTime.parse(json['lastOrderedAt'] as String),
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => FrequentlyBoughtGroupItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalPrice: json['totalPrice'] as int,
      anyUnavailable: json['anyUnavailable'] as bool,
    );
  }
}

class FrequentlyBoughtGroupItem {
  const FrequentlyBoughtGroupItem({
    required this.variantId,
    required this.productId,
    required this.productName,
    this.isVeg,
    required this.unitValue,
    required this.unitLabel,
    required this.price,
    this.mrp,
    this.imageUrl,
    required this.isAvailable,
  });

  final String variantId;
  final String productId;
  final String productName;
  final bool? isVeg;
  final String unitValue;
  final String unitLabel;
  final int price;
  final int? mrp;
  final String? imageUrl;
  final bool isAvailable;

  factory FrequentlyBoughtGroupItem.fromJson(Map<String, dynamic> json) {
    return FrequentlyBoughtGroupItem(
      variantId: json['variantId'] as String,
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      isVeg: json['isVeg'] as bool?,
      unitValue: json['unitValue'] as String,
      unitLabel: json['unitLabel'] as String,
      price: json['price'] as int,
      mrp: json['mrp'] as int?,
      imageUrl: json['imageUrl'] as String?,
      isAvailable: json['isAvailable'] as bool,
    );
  }
}
