import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wallet.dart';
import '../models/invite.dart';
import '../models/wallet_member.dart';
import '../config/api_config.dart';
import 'auth_service.dart';
import 'cache_service.dart';

class WalletService {
  final AuthService _authService = AuthService();
  final CacheService _cacheService = CacheService();

  static String get baseUrl => ApiConfig.baseUrl;

  Map<String, String> _getHeaders() {
    final token = _authService.currentAccessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Wallets
  Future<List<Wallet>> getAllWallets({bool forceRefresh = false}) async {
    try {
      // Tentar obter do cache primeiro (se não for refresh forçado)
      if (!forceRefresh) {
        final cachedWallets = await _cacheService.getCachedWallets();
        if (cachedWallets != null) {
          return cachedWallets;
        }
      }

      // Se não houver cache válido, buscar da API
      final response = await http.get(
        Uri.parse('$baseUrl/wallets'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        final wallets = decoded.map((json) => Wallet.fromJson(json)).toList();
        
        // Salvar no cache
        await _cacheService.cacheWallets(wallets);
        
        return wallets;
      } else {
        // Em caso de erro, tentar retornar do cache
        final cachedWallets = await _cacheService.getCachedWallets();
        if (cachedWallets != null) {
          return cachedWallets;
        }
        throw Exception('Failed to load wallets: ${response.statusCode}');
      }
    } catch (e) {
      // Em caso de erro de rede, tentar retornar do cache
      final cachedWallets = await _cacheService.getCachedWallets();
      if (cachedWallets != null) {
        return cachedWallets;
      }
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

      rethrow;
    }
  }

  Future<List<WalletMember>> getWalletMembers(String walletId, {bool forceRefresh = false}) async {
    try {
      // Tentar obter do cache primeiro (se não for refresh forçado)
      if (!forceRefresh) {
        final cachedMembers = await _cacheService.getCachedWalletMembers(walletId);
        if (cachedMembers != null) {
          return cachedMembers;
        }
      }

      // Se não houver cache válido, buscar da API
      final response = await http.get(
        Uri.parse('$baseUrl/wallets/$walletId/members'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        final members = decoded.map((json) => WalletMember.fromJson(json)).toList();
        
        // Salvar no cache
        await _cacheService.cacheWalletMembers(walletId, members);
        
        return members;
      } else {
        // Em caso de erro, tentar retornar do cache
        final cachedMembers = await _cacheService.getCachedWalletMembers(walletId);
        if (cachedMembers != null) {
          return cachedMembers;
        }
        throw Exception('Failed to load wallet members: ${response.statusCode}');
      }
    } catch (e) {
      // Em caso de erro de rede, tentar retornar do cache
      final cachedMembers = await _cacheService.getCachedWalletMembers(walletId);
      if (cachedMembers != null) {
        return cachedMembers;
      }
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
      
      // Invalidar cache de membros da wallet
      await _cacheService.invalidateWalletMembersCache(walletId);
    } catch (e) {

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
      
      // Invalidar cache de membros da wallet e invites (permissão pode afetar invites)
      await _cacheService.invalidateWalletMembersCache(walletId);
      await _cacheService.invalidateInvitesCache(walletId);
    } catch (e) {

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
        final invite = Invite.fromJson(decoded);
        
        // Invalidar cache de invites para forçar refresh na próxima vez
        await _cacheService.invalidateInvitesCache(walletId);
        
        return invite;
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to create invite');
      }
    } catch (e) {

      rethrow;
    }
  }

  Future<List<Invite>> getWalletInvites(String walletId, {bool forceRefresh = false}) async {
    try {
      // Tentar obter do cache primeiro (se não for refresh forçado)
      if (!forceRefresh) {
        final cachedInvites = await _cacheService.getCachedInvites(walletId);
        if (cachedInvites != null) {
          return cachedInvites;
        }
      }

      // Se não houver cache válido, buscar da API
      final response = await http.get(
        Uri.parse('$baseUrl/invites/wallet/$walletId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        final invites = decoded.map((json) => Invite.fromJson(json)).toList();
        
        // Salvar no cache
        await _cacheService.cacheInvites(walletId, invites);
        
        return invites;
      } else {
        // Em caso de erro, tentar retornar do cache
        final cachedInvites = await _cacheService.getCachedInvites(walletId);
        if (cachedInvites != null) {
          return cachedInvites;
        }
        throw Exception('Failed to load invites: ${response.statusCode}');
      }
    } catch (e) {
      // Em caso de erro de rede, tentar retornar do cache
      final cachedInvites = await _cacheService.getCachedInvites(walletId);
      if (cachedInvites != null) {
        return cachedInvites;
      }
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
        final result = json.decode(response.body);
        
        // Invalidar cache de wallets para forçar refresh na próxima busca
        // Isso garante que a wallet aceita apareça imediatamente
        await _cacheService.invalidateWalletsCache();
        
        // Também invalidar cache de usuário para garantir que walletsInvited está atualizado
        await _cacheService.invalidateUserCache();
        
        return result;
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to accept invite');
      }
    } catch (e) {

      rethrow;
    }
  }

  Future<void> cancelInvite(String token, String walletId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/invites/$token'),
        headers: _getHeaders(),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to cancel invite');
      }
      
      // Invalidar cache de invites para forçar refresh na próxima vez
      await _cacheService.invalidateInvitesCache(walletId);
    } catch (e) {

      rethrow;
    }
  }
}
