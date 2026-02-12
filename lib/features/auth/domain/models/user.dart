class User {
  final String id;
  final String username;
  final String email;
  final String? avatar;
  final DateTime expireDate;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.avatar,
    required this.expireDate,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().isAfter(expireDate);

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      avatar: json['avatar'],
      expireDate: DateTime.parse(json['expire_date'] ?? json['expireDate']),
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar': avatar,
      'expire_date': expireDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? avatar,
    DateTime? expireDate,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      expireDate: expireDate ?? this.expireDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
