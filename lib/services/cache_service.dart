import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';
import '../models/period_history.dart';
import '../models/user.dart';
import '../models/wallet_member.dart';
import '../models/wallet.dart';
import '../models/invite.dart';

class CacheService {
  static const String _transactionsKey = 'cached_transactions';
  static const String _periodHistoriesKey = 'cached_period_histories';
  static const String _lastUpdateKey = 'cache_last_update';
  static const String _currentPeriodKey = 'cached_current_period';
  static const String _userKey = 'cached_user';
  static const String _userLastUpdateKey = 'cache_user_last_update';
  static const String _walletMembersPrefix = 'cached_wallet_members_';
  static const String _walletsKey = 'cached_wallets';
  static const String _walletsLastUpdateKey = 'cache_wallets_last_update';
  static const String _invitesPrefix = 'cached_invites_';
  
  // Cache válido por 2 minutos (equilíbrio entre consistência e performance)
  static const Duration cacheValidityDuration = Duration(minutes: 2);
  // Cache de usuário válido por 5 minutos (muda menos frequentemente)
  static const Duration userCacheValidityDuration = Duration(minutes: 5);
  // Cache de membros da wallet válido por 2 minutos
  static const Duration walletMembersCacheValidityDuration = Duration(minutes: 2);
  // Cache de wallets válido por 3 minutos
  static const Duration walletsCacheValidityDuration = Duration(minutes: 3);
  // Cache de invites válido por 1 minuto (mudam mais frequentemente)
  static const Duration invitesCacheValidityDuration = Duration(minutes: 1);

  // Salvar transações no cache (usando compute para não bloquear UI)
  Future<void> cacheTransactions(List<Transaction> transactions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Usar compute para fazer encoding em background
      final transactionsJson = await compute(_encodeTransactions, transactions);
      await prefs.setString(_transactionsKey, transactionsJson);
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {

    }
  }

  // Função isolada para encoding
  static String _encodeTransactions(List<Transaction> transactions) {
    return json.encode(
      transactions.map((t) => t.toJson()).toList(),
    );
  }

  // Obter transações do cache (usando compute para não bloquear UI)
  Future<List<Transaction>?> getCachedTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final transactionsJson = prefs.getString(_transactionsKey);
      
      if (transactionsJson == null) {
        return null;
      }

      // Usar compute para fazer decoding em background
      final decoded = await compute(_decodeTransactions, transactionsJson);
      return decoded;
    } catch (e) {

      return null;
    }
  }

  // Função isolada para decoding
  static List<Transaction> _decodeTransactions(String jsonString) {
    final List<dynamic> decoded = json.decode(jsonString);
    return decoded.map((json) => Transaction.fromJson(json)).toList();
  }

  // Salvar períodos no cache
  Future<void> cachePeriodHistories(List<PeriodHistory> periods) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final periodsJson = json.encode(
        periods.map((p) => p.toJson()).toList(),
      );
      await prefs.setString(_periodHistoriesKey, periodsJson);
    } catch (e) {

    }
  }

  // Obter períodos do cache
  Future<List<PeriodHistory>?> getCachedPeriodHistories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final periodsJson = prefs.getString(_periodHistoriesKey);
      
      if (periodsJson == null) {
        return null;
      }

      final List<dynamic> decoded = json.decode(periodsJson);
      return decoded.map((json) => PeriodHistory.fromJson(json)).toList();
    } catch (e) {

      return null;
    }
  }

  // Verificar se o cache é válido
  Future<bool> isCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      
      if (lastUpdateStr == null) {
        return false;
      }

      final lastUpdate = DateTime.parse(lastUpdateStr);
      final now = DateTime.now();
      return now.difference(lastUpdate) < cacheValidityDuration;
    } catch (e) {
      return false;
    }
  }

  // Salvar período atual no cache
  Future<void> cacheCurrentPeriod({
    required DateTime startDate,
    required DateTime endDate,
    required int selectedYear,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentPeriodKey, json.encode({
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'selectedYear': selectedYear,
      }));
    } catch (e) {

    }
  }

  // Obter período atual do cache
  Future<Map<String, dynamic>?> getCachedCurrentPeriod() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final periodJson = prefs.getString(_currentPeriodKey);
      
      if (periodJson == null) {
        return null;
      }

      final decoded = json.decode(periodJson) as Map<String, dynamic>;
      return {
        'startDate': DateTime.parse(decoded['startDate'] as String),
        'endDate': DateTime.parse(decoded['endDate'] as String),
        'selectedYear': decoded['selectedYear'] as int,
      };
    } catch (e) {

      return null;
    }
  }

  // Limpar cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_transactionsKey);
      await prefs.remove(_periodHistoriesKey);
      await prefs.remove(_lastUpdateKey);
      await prefs.remove(_currentPeriodKey);
    } catch (e) {

    }
  }

  // Invalidar cache (forçar atualização)
  Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastUpdateKey);
    } catch (e) {

    }
  }

  // ========== CACHE DE USUÁRIO ==========
  
  // Salvar usuário no cache
  Future<void> cacheUser(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, json.encode(user.toJson()));
      await prefs.setString(_userLastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      // Ignorar erros de cache
    }
  }

  // Obter usuário do cache
  Future<User?> getCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      final lastUpdateStr = prefs.getString(_userLastUpdateKey);
      
      if (userJson == null || lastUpdateStr == null) {
        return null;
      }

      // Verificar se o cache é válido
      final lastUpdate = DateTime.parse(lastUpdateStr);
      final now = DateTime.now();
      if (now.difference(lastUpdate) > userCacheValidityDuration) {
        return null; // Cache expirado
      }

      final decoded = json.decode(userJson) as Map<String, dynamic>;
      return User.fromJson(decoded);
    } catch (e) {
      return null;
    }
  }

  // Verificar se o cache de usuário é válido
  Future<bool> isUserCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString(_userLastUpdateKey);
      
      if (lastUpdateStr == null) {
        return false;
      }

      final lastUpdate = DateTime.parse(lastUpdateStr);
      final now = DateTime.now();
      return now.difference(lastUpdate) < userCacheValidityDuration;
    } catch (e) {
      return false;
    }
  }

  // Invalidar cache de usuário
  Future<void> invalidateUserCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      await prefs.remove(_userLastUpdateKey);
    } catch (e) {
      // Ignorar erros
    }
  }

  // ========== CACHE DE MEMBROS DA WALLET ==========
  
  // Salvar membros da wallet no cache
  Future<void> cacheWalletMembers(String walletId, List<WalletMember> members) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_walletMembersPrefix$walletId';
      final lastUpdateKey = '${_walletMembersPrefix}${walletId}_last_update';
      
      final membersJson = json.encode(
        members.map((m) => m.toJson()).toList(),
      );
      await prefs.setString(key, membersJson);
      await prefs.setString(lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      // Ignorar erros de cache
    }
  }

  // Obter membros da wallet do cache
  Future<List<WalletMember>?> getCachedWalletMembers(String walletId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_walletMembersPrefix$walletId';
      final lastUpdateKey = '${_walletMembersPrefix}${walletId}_last_update';
      
      final membersJson = prefs.getString(key);
      final lastUpdateStr = prefs.getString(lastUpdateKey);
      
      if (membersJson == null || lastUpdateStr == null) {
        return null;
      }

      // Verificar se o cache é válido
      final lastUpdate = DateTime.parse(lastUpdateStr);
      final now = DateTime.now();
      if (now.difference(lastUpdate) > walletMembersCacheValidityDuration) {
        return null; // Cache expirado
      }

      final List<dynamic> decoded = json.decode(membersJson);
      return decoded.map((json) => WalletMember.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  // Invalidar cache de membros da wallet
  Future<void> invalidateWalletMembersCache(String walletId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_walletMembersPrefix$walletId';
      final lastUpdateKey = '${_walletMembersPrefix}${walletId}_last_update';
      await prefs.remove(key);
      await prefs.remove(lastUpdateKey);
    } catch (e) {
      // Ignorar erros
    }
  }

  // Limpar todos os caches de membros de wallets
  Future<void> clearAllWalletMembersCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_walletMembersPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      // Ignorar erros
    }
  }

  // ========== CACHE DE WALLETS ==========
  
  // Salvar wallets no cache
  Future<void> cacheWallets(List<Wallet> wallets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final walletsJson = json.encode(
        wallets.map((w) => w.toJson()).toList(),
      );
      await prefs.setString(_walletsKey, walletsJson);
      await prefs.setString(_walletsLastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      // Ignorar erros de cache
    }
  }

  // Obter wallets do cache
  Future<List<Wallet>?> getCachedWallets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final walletsJson = prefs.getString(_walletsKey);
      final lastUpdateStr = prefs.getString(_walletsLastUpdateKey);
      
      if (walletsJson == null || lastUpdateStr == null) {
        return null;
      }

      // Verificar se o cache é válido
      final lastUpdate = DateTime.parse(lastUpdateStr);
      final now = DateTime.now();
      if (now.difference(lastUpdate) > walletsCacheValidityDuration) {
        return null; // Cache expirado
      }

      final List<dynamic> decoded = json.decode(walletsJson);
      return decoded.map((json) => Wallet.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  // Invalidar cache de wallets
  Future<void> invalidateWalletsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_walletsKey);
      await prefs.remove(_walletsLastUpdateKey);
    } catch (e) {
      // Ignorar erros
    }
  }

  // ========== CACHE DE INVITES ==========
  
  // Salvar invites da wallet no cache
  Future<void> cacheInvites(String walletId, List<Invite> invites) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_invitesPrefix$walletId';
      final lastUpdateKey = '${_invitesPrefix}${walletId}_last_update';
      
      final invitesJson = json.encode(
        invites.map((i) => i.toJson()).toList(),
      );
      await prefs.setString(key, invitesJson);
      await prefs.setString(lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      // Ignorar erros de cache
    }
  }

  // Obter invites da wallet do cache
  Future<List<Invite>?> getCachedInvites(String walletId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_invitesPrefix$walletId';
      final lastUpdateKey = '${_invitesPrefix}${walletId}_last_update';
      
      final invitesJson = prefs.getString(key);
      final lastUpdateStr = prefs.getString(lastUpdateKey);
      
      if (invitesJson == null || lastUpdateStr == null) {
        return null;
      }

      // Verificar se o cache é válido
      final lastUpdate = DateTime.parse(lastUpdateStr);
      final now = DateTime.now();
      if (now.difference(lastUpdate) > invitesCacheValidityDuration) {
        return null; // Cache expirado
      }

      final List<dynamic> decoded = json.decode(invitesJson);
      return decoded.map((json) => Invite.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  // Invalidar cache de invites da wallet
  Future<void> invalidateInvitesCache(String walletId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_invitesPrefix$walletId';
      final lastUpdateKey = '${_invitesPrefix}${walletId}_last_update';
      await prefs.remove(key);
      await prefs.remove(lastUpdateKey);
    } catch (e) {
      // Ignorar erros
    }
  }

  // Limpar todos os caches de invites
  Future<void> clearAllInvitesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_invitesPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      // Ignorar erros
    }
  }
}
