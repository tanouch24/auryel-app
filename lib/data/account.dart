/// Compte Auryel renvoyé par `GET /api/account`. `userId` est l'identité
/// technique (UUID `accounts.user_id` côté backend) — jamais l'email.
class Account {
  const Account({
    required this.userId,
    required this.email,
    this.createdAt,
    this.lastLoginAt,
  });

  final String userId;
  final String email;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  factory Account.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return Account(
      userId: (json['user_id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      createdAt: parse(json['created_at']),
      lastLoginAt: parse(json['last_login_at']),
    );
  }
}
