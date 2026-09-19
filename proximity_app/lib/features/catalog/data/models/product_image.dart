/// Mirrors `product_images` rows nested in `GET /v1/shops/:shopId/products`
/// and `GET /v1/products/:id` (routes/catalog.ts) -- already-sorted by
/// `sortOrder` server-side, same "server sorts, client doesn't re-sort"
/// convention `GET /shops/near` established for distance (Sprint 4).
class ProductImage {
  const ProductImage({required this.id, required this.imageUrl});

  final String id;
  final String imageUrl;

  factory ProductImage.fromJson(Map<String, dynamic> json) {
    return ProductImage(id: json['id'] as String, imageUrl: json['imageUrl'] as String);
  }

  // Sprint 15 -- local cache round-trip (core/cache), not the network.
  Map<String, dynamic> toJson() => {'id': id, 'imageUrl': imageUrl};
}
