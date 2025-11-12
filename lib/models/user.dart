class User {
  final String userId;
  final String email;
  final String name;
  final String? personalWalletId;
  final List<String> walletsInvited;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  User({
    required this.userId,
    required this.email,
    required this.name,
    this.personalWalletId,
    List<String>? walletsInvited,
    this.createdAt,
    this.updatedAt,
  }) : walletsInvited = walletsInvited ?? [];

  factory User.fromJson(Map<String, dynamic> json) {
    // Converter walletsInvited de array de objetos/strings para lista de strings
    List<String> walletsInvitedList = [];
    if (json['walletsInvited'] != null) {
      final walletsInvitedData = json['walletsInvited'];
      if (walletsInvitedData is List) {
        walletsInvitedList = walletsInvitedData.map((item) {
          if (item is String) {
            return item;
          } else if (item is Map && item['_id'] != null) {
            return item['_id'].toString();
          } else {
            return item.toString();
          }
        }).toList().cast<String>();
      }
    }

    // Converter personalWalletId de objeto para string se necessário
    String? personalWalletIdStr;
    if (json['personalWalletId'] != null) {
      if (json['personalWalletId'] is String) {
        personalWalletIdStr = json['personalWalletId'] as String;
      } else if (json['personalWalletId'] is Map && json['personalWalletId']['_id'] != null) {
        personalWalletIdStr = json['personalWalletId']['_id'].toString();
      } else {
        personalWalletIdStr = json['personalWalletId'].toString();
      }
    }

    return User(
      userId: json['userId'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      personalWalletId: personalWalletIdStr,
      walletsInvited: walletsInvitedList,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'name': name,
      'personalWalletId': personalWalletId,
      'walletsInvited': walletsInvited,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

