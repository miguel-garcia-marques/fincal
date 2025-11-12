import 'wallet.dart';

class Invite {
  final String id;
  final String walletId;
  final String invitedBy;
  final String? invitedByName;
  final String? email;
  final String token;
  final String permission; // 'read', 'write'
  final String status; // 'pending', 'accepted', 'expired'
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final String? acceptedBy;
  final String? acceptedByName;
  final Wallet? wallet; // Wallet associada (quando populada)

  Invite({
    required this.id,
    required this.walletId,
    required this.invitedBy,
    this.invitedByName,
    this.email,
    required this.token,
    required this.permission,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.acceptedAt,
    this.acceptedBy,
    this.acceptedByName,
    this.wallet,
  });

  bool get isExpired {
    return DateTime.now().isAfter(expiresAt);
  }

  bool get isPending {
    return status == 'pending' && !isExpired;
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'walletId': walletId,
      'invitedBy': invitedBy,
      'invitedByName': invitedByName,
      'email': email,
      'token': token,
      'permission': permission,
      'status': status,
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'acceptedAt': acceptedAt?.toIso8601String(),
      'acceptedBy': acceptedBy,
      'acceptedByName': acceptedByName,
    };
  }

  factory Invite.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic dateValue, String fieldName) {
      try {
        // Se for null ou não existir, retornar data atual como fallback
        if (dateValue == null) {
          print('Warning: $fieldName is null, using current date as fallback');
          return DateTime.now();
        }
        
        if (dateValue is String) {
          final trimmed = dateValue.trim();
          if (trimmed.isEmpty || trimmed == 'null' || trimmed == 'undefined') {
            print('Warning: $fieldName is empty or "null" string, using current date as fallback');
            return DateTime.now();
          }
          try {
            return DateTime.parse(trimmed);
          } catch (e) {
            // Se falhar o parse, retornar data atual
            print('Error parsing $fieldName: "$dateValue", error: $e');
            return DateTime.now();
          }
        } else if (dateValue is Map) {
          final dateStr = dateValue['\$date'] as String? ?? dateValue.toString();
          try {
            return DateTime.parse(dateStr);
          } catch (e) {
            print('Error parsing $fieldName from map: $dateValue, error: $e');
            return DateTime.now();
          }
        } else if (dateValue is DateTime) {
          return dateValue;
        } else {
          // Fallback para data atual se não conseguir parsear
          print('Unknown $fieldName format: $dateValue (${dateValue.runtimeType}), using current date as fallback');
          return DateTime.now();
        }
      } catch (e) {
        // Catch-all para qualquer erro inesperado
        print('Critical error parsing $fieldName: $e, using current date as fallback');
        return DateTime.now();
      }
    }

    DateTime? parseDateNullable(dynamic dateValue) {
      if (dateValue == null) return null;
      if (dateValue is String) {
        if (dateValue.isEmpty || dateValue.trim() == 'null') return null;
        try {
          return DateTime.parse(dateValue);
        } catch (e) {
          return null;
        }
      } else if (dateValue is Map) {
        final dateStr = dateValue['\$date'] as String? ?? dateValue.toString();
        try {
          return DateTime.parse(dateStr);
        } catch (e) {
          return null;
        }
      } else if (dateValue is DateTime) {
        return dateValue;
      } else {
        return null;
      }
    }

    Wallet? wallet;
    try {
      if (json['wallet'] is Map) {
        wallet = Wallet.fromJson(json['wallet'] as Map<String, dynamic>);
      } else if (json['walletId'] is Map) {
        wallet = Wallet.fromJson(json['walletId'] as Map<String, dynamic>);
      }
    } catch (e) {
      print('Error parsing wallet in invite: $e');
      wallet = null;
    }

    // Garantir que expiresAt e createdAt nunca sejam null
    // Usar try-catch para capturar qualquer erro durante o parsing
    DateTime expiresAt;
    DateTime createdAt;
    
    try {
      expiresAt = parseDate(json['expiresAt'], 'expiresAt');
    } catch (e) {
      print('Critical error parsing expiresAt: $e, using fallback');
      expiresAt = DateTime.now();
    }
    
    try {
      createdAt = parseDate(json['createdAt'], 'createdAt');
    } catch (e) {
      print('Critical error parsing createdAt: $e, using fallback');
      createdAt = DateTime.now();
    }

    return Invite(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      walletId: json['walletId'] is Map
          ? (json['walletId'] as Map)['_id']?.toString() ?? ''
          : json['walletId']?.toString() ?? '',
      invitedBy: json['invitedBy'] as String? ?? '',
      invitedByName: json['invitedByName'] as String?,
      email: json['email'] as String?,
      token: json['token'] as String? ?? '',
      permission: json['permission'] as String? ?? 'read',
      status: json['status'] as String? ?? 'pending',
      expiresAt: expiresAt,
      createdAt: createdAt,
      acceptedAt: parseDateNullable(json['acceptedAt']),
      acceptedBy: json['acceptedBy'] as String?,
      acceptedByName: json['acceptedByName'] as String?,
      wallet: wallet,
    );
  }
}

