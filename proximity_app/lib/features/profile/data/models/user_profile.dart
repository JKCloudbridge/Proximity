/// The logged-in user's account info -- shape of POST /v1/auth/me's `user`
/// object (proximity_backend/.../routes/auth.ts). Deliberately smaller than
/// Baker Ally's UserProfile: no businessName/gstin here (those are shop
/// fields now, on `shops`, not `users` -- SPRINT_PLANNING.md §4.4) since
/// Proximity separates "buyer account" from "shop" instead of overloading
/// one profile record with both.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.role,
    this.fullName,
    this.phone,
    this.email,
    this.avatarUrl,
  });

  final String id;
  final String role;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? avatarUrl;

  /// Fallback shown wherever an avatar would go but none is set yet -- same
  /// initials-badge convention as Baker Ally's UserProfile.initials.
  String get initials {
    final name = fullName?.trim();
    if (name == null || name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return UserProfile(
      id: user['id'] as String,
      role: json['role'] as String? ?? user['role'] as String? ?? 'buyer',
      fullName: user['fullName'] as String?,
      phone: user['phone'] as String?,
      email: user['email'] as String?,
      avatarUrl: user['avatarUrl'] as String?,
    );
  }
}
