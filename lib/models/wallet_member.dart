class WalletMember {
  final String walletId;
  final String userId;
  final String permission; // 'read', 'write', 'owner'
  final DateTime joinedAt;
  final String? email;
  final String? name;
  final bool isOwner;

  WalletMember({
    required this.walletId,
    required this.userId,
    required this.permission,
    required this.joinedAt,
    this.email,
    this.name,
    this.isOwner = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'walletId': walletId,
      'userId': userId,
      'permission': permission,
      'joinedAt': joinedAt.toIso8601String(),
      'email': email,
      'name': name,
      'isOwner': isOwner,
    };
  }

  factory WalletMember.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic dateValue) {
      if (dateValue is String) {
        return DateTime.parse(dateValue);
      } else if (dateValue is Map) {
        final dateStr = dateValue['\$date'] as String? ?? dateValue.toString();
        return DateTime.parse(dateStr);
      } else {
        return dateValue as DateTime;
      }
    }

    return WalletMember(
      walletId: json['walletId']?.toString() ?? '',
      userId: json['userId'] as String? ?? '',
      permission: json['permission'] as String? ?? 'read',
      joinedAt: parseDate(json['joinedAt']),
      email: json['email'] as String?,
      name: json['name'] as String?,
      isOwner: json['isOwner'] as bool? ?? false,
    );
  }
}

