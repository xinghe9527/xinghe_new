import 'package:flutter/foundation.dart';

class User {
  final String id;
  final String username;
  final String email;
  final String? avatar;
  final bool verified;
  final DateTime expireDate;
  final DateTime createdAt;
  final String? lastDeviceId;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.avatar,
    this.verified = false,
    required this.expireDate,
    required this.createdAt,
    this.lastDeviceId,
  });

  bool get isExpired => DateTime.now().isAfter(expireDate);

  factory User.fromJson(Map<String, dynamic> json) {
    // 调试输出：查看原始 JSON 数据
    debugPrint('=== User.fromJson 解析 ===');
    debugPrint('原始 JSON: $json');
    debugPrint('name 字段: ${json['name']}');
    debugPrint('username 字段: ${json['username']}');
    debugPrint('========================');
    
    // PocketBase 可能使用 name 或 username 字段，优先使用 name
    String username = json['name'] ?? json['username'] ?? '';
    if (username.isEmpty) {
      username = '未命名用户';
    }
    
    return User(
      id: json['_id'] ?? json['id'] ?? '',
      username: username,
      email: json['email'] ?? '',
      avatar: json['avatar'],
      verified: json['verified'] ?? false,
      expireDate: DateTime.parse(json['expire_date'] ?? json['expireDate']),
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastDeviceId: json['last_device_id'] ?? json['lastDeviceId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar': avatar,
      'verified': verified,
      'expire_date': expireDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'last_device_id': lastDeviceId,
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? avatar,
    bool? verified,
    DateTime? expireDate,
    DateTime? createdAt,
    String? lastDeviceId,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      verified: verified ?? this.verified,
      expireDate: expireDate ?? this.expireDate,
      createdAt: createdAt ?? this.createdAt,
      lastDeviceId: lastDeviceId ?? this.lastDeviceId,
    );
  }
}
