import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wallet.dart';
import '../models/invite.dart';
import '../models/wallet_member.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

class WalletService {
  final AuthService _authService = AuthService();

  static String get baseUrl => ApiConfig.baseUrl;

  Map<String, String> _getHeaders() {
    final token = _authService.currentAccessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Wallets
  Future<List<Wallet>> getAllWallets() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wallets'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => Wallet.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load wallets: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching wallets: $e');
      return [];
    }
  }

  Future<Wallet> getWallet(String walletId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wallets/$walletId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return Wallet.fromJson(decoded);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to load wallet');
      }
    } catch (e) {
      print('Error fetching wallet: $e');
      rethrow;
    }
  }

  Future<Wallet> createWallet({String? name}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/wallets'),
        headers: _getHeaders(),
        body: json.encode({'name': name ?? 'Minha Carteira Calendário'}),
      );

      if (response.statusCode == 201) {
        final decoded = json.decode(response.body);
        return Wallet.fromJson(decoded);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to create wallet');
      }
    } catch (e) {
      print('Error creating wallet: $e');
      rethrow;
    }
  }

  Future<Wallet> updateWallet(String walletId, String name) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/wallets/$walletId'),
        headers: _getHeaders(),
        body: json.encode({'name': name}),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return Wallet.fromJson(decoded);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update wallet');
      }
    } catch (e) {
      print('Error updating wallet: $e');
      rethrow;
    }
  }

  Future<void> deleteWallet(String walletId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/wallets/$walletId'),
        headers: _getHeaders(),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to delete wallet');
      }
    } catch (e) {
      print('Error deleting wallet: $e');
      rethrow;
    }
  }

  Future<List<WalletMember>> getWalletMembers(String walletId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wallets/$walletId/members'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => WalletMember.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load wallet members: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching wallet members: $e');
      return [];
    }
  }

  Future<void> removeWalletMember(String walletId, String userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/wallets/$walletId/members/$userId'),
        headers: _getHeaders(),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to remove member');
      }
    } catch (e) {
      print('Error removing wallet member: $e');
      rethrow;
    }
  }

  Future<void> updateMemberPermission(String walletId, String userId, String permission) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/wallets/$walletId/members/$userId'),
        headers: _getHeaders(),
        body: json.encode({'permission': permission}),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update permission');
      }
    } catch (e) {
      print('Error updating member permission: $e');
      rethrow;
    }
  }

  // Invites
  Future<Invite> createInvite({
    required String walletId,
    String? email,
    required String permission, // 'read' or 'write'
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/invites'),
        headers: _getHeaders(),
        body: json.encode({
          'walletId': walletId,
          'email': email,
          'permission': permission,
        }),
      );

      if (response.statusCode == 201) {
        final decoded = json.decode(response.body);
        return Invite.fromJson(decoded);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to create invite');
      }
    } catch (e) {
      print('Error creating invite: $e');
      rethrow;
    }
  }

  Future<List<Invite>> getWalletInvites(String walletId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/invites/wallet/$walletId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => Invite.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load invites: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching invites: $e');
      return [];
    }
  }

  Future<List<Invite>> getPendingInvites() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/invites/pending'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => Invite.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load pending invites: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching pending invites: $e');
      return [];
    }
  }

  Future<Invite> getInviteByToken(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/invites/token/$token'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return Invite.fromJson(decoded);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to load invite');
      }
    } catch (e) {
      print('Error fetching invite: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> acceptInvite(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/invites/$token/accept'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to accept invite');
      }
    } catch (e) {
      print('Error accepting invite: $e');
      rethrow;
    }
  }

  Future<void> cancelInvite(String token) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/invites/$token'),
        headers: _getHeaders(),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to cancel invite');
      }
    } catch (e) {
      print('Error canceling invite: $e');
      rethrow;
    }
  }
}

