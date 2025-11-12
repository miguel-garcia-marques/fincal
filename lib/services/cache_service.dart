import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';
import '../models/period_history.dart';

class CacheService {
  static const String _transactionsKey = 'cached_transactions';
  static const String _periodHistoriesKey = 'cached_period_histories';
  static const String _lastUpdateKey = 'cache_last_update';
  static const String _currentPeriodKey = 'cached_current_period';
  
  // Cache válido por 5 minutos (aumentado para reduzir requisições)
  static const Duration cacheValidityDuration = Duration(minutes: 5);

  // Salvar transações no cache (usando compute para não bloquear UI)
  Future<void> cacheTransactions(List<Transaction> transactions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Usar compute para fazer encoding em background
      final transactionsJson = await compute(_encodeTransactions, transactions);
      await prefs.setString(_transactionsKey, transactionsJson);
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      print('Erro ao salvar transações no cache: $e');
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
      print('Erro ao ler transações do cache: $e');
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
      print('Erro ao salvar períodos no cache: $e');
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
      print('Erro ao ler períodos do cache: $e');
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
      print('Erro ao salvar período atual no cache: $e');
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
      print('Erro ao ler período atual do cache: $e');
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
      print('Erro ao limpar cache: $e');
    }
  }

  // Invalidar cache (forçar atualização)
  Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastUpdateKey);
    } catch (e) {
      print('Erro ao invalidar cache: $e');
    }
  }
}

