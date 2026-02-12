class InvitationCode {
  final String id;
  final String code;
  final int durationDays;
  final bool isUsed;
  final DateTime? usedAt;
  final String? usedBy;

  InvitationCode({
    required this.id,
    required this.code,
    required this.durationDays,
    required this.isUsed,
    this.usedAt,
    this.usedBy,
  });

  factory InvitationCode.fromJson(Map<String, dynamic> json) {
    return InvitationCode(
      id: json['_id'] ?? json['id'] ?? '',
      code: json['code'] ?? '',
      durationDays: json['duration_days'] ?? json['durationDays'] ?? 0,
      isUsed: json['is_used'] ?? json['isUsed'] ?? false,
      usedAt: json['used_at'] != null ? DateTime.parse(json['used_at']) : null,
      usedBy: json['used_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'duration_days': durationDays,
      'is_used': isUsed,
      'used_at': usedAt?.toIso8601String(),
      'used_by': usedBy,
    };
  }
}
