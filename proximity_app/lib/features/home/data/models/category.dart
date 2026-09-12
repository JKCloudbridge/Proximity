/// Mirrors `GET /v1/categories` (routes/categories.ts) -- the global,
/// admin-curated 20-item list (SPRINT_PLANNING.md §4.3), unauthenticated,
/// powers the Home category chip row (§7.1).
class Category {
  const Category({required this.id, required this.name, this.icon, this.imageUrl, required this.sortOrder});

  final String id;
  final String name;
  final String? icon;
  final String? imageUrl;
  final int sortOrder;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      imageUrl: json['imageUrl'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }
}
