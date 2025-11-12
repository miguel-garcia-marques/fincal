class Wallet {
  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String permission; // 'owner', 'read', 'write'
  final bool isOwner;
  final String? ownerName;

  Wallet({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    required this.permission,
    required this.isOwner,
    this.ownerName,
  });

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'ownerId': ownerId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'permission': permission,
      'isOwner': isOwner,
      'ownerName': ownerName,
    };
  }

  factory Wallet.fromJson(Map<String, dynamic> json) {
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

    return Wallet(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Minha Carteira Calendário',
      ownerId: json['ownerId'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      permission: json['permission'] as String? ?? 'read',
      isOwner: json['isOwner'] as bool? ?? false,
      ownerName: json['ownerName'] as String?,
    );
  }
}

