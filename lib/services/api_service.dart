import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';
import '../models/period_history.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

class ApiService {
  final AuthService _authService = AuthService();

  // Usa a configuração centralizada da API
  static String get baseUrl => ApiConfig.baseUrl;

  // Obter headers com autenticação
  Map<String, String> _getHeaders() {
    final token = _authService.currentAccessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<Transaction>> getAllTransactions({required String walletId}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/transactions?walletId=$walletId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        // Usar compute para parsing em background (não bloquear UI)
        return await compute(_parseTransactions, response.body);
      } else {
        throw Exception('Failed to load transactions: ${response.statusCode}');
      }
    } catch (e) {

      return [];
    }
  }

  Future<void> saveTransaction(Transaction transaction, {required String walletId}) async {
    try {
      final transactionJson = transaction.toJson();
      transactionJson['walletId'] = walletId;
      
      final response = await http.post(
        Uri.parse('$baseUrl/transactions'),
        headers: _getHeaders(),
        body: json.encode(transactionJson),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to save transaction');
      }
    } catch (e) {

      rethrow;
    }
  }

  Future<void> updateTransaction(Transaction transaction, {required String walletId}) async {
    try {
      final transactionJson = transaction.toJson();
      transactionJson['walletId'] = walletId;
      
      final response = await http.put(
        Uri.parse('$baseUrl/transactions/${transaction.id}'),
        headers: _getHeaders(),
        body: json.encode(transactionJson),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update transaction');
      }
    } catch (e) {

      rethrow;
    }
  }

  Future<void> deleteTransaction(String id, {required String walletId}) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/transactions/$id?walletId=$walletId'),
        headers: _getHeaders(),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to delete transaction');
      }
    } catch (e) {

      rethrow;
    }
  }

  Future<List<Transaction>> getTransactionsInRange(
    DateTime startDate,
    DateTime endDate, {
    required String walletId,
  }) async {
    try {
      final startStr = _formatDateForApi(startDate);
      final endStr = _formatDateForApi(endDate);
      
      final response = await http.get(
        Uri.parse('$baseUrl/transactions/range?startDate=$startStr&endDate=$endStr&walletId=$walletId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        // Usar compute para parsing em background (não bloquear UI)
        return await compute(_parseTransactions, response.body);
      } else {
        throw Exception('Failed to load transactions: ${response.statusCode}');
      }
    } catch (e) {

      return [];
    }
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Period History methods
  Future<List<PeriodHistory>> getAllPeriodHistories({String? ownerId}) async {
    try {
      final uri = ownerId != null
          ? Uri.parse('$baseUrl/period-history?ownerId=$ownerId')
          : Uri.parse('$baseUrl/period-history');
      
      final response = await http.get(
        uri,
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => PeriodHistory.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load period histories: ${response.statusCode}');
      }
    } catch (e) {

      return [];
    }
  }

  Future<PeriodHistory> getPeriodHistory(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/period-history/$id'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return PeriodHistory.fromJson(decoded);
      } else {
        throw Exception('Failed to load period history: ${response.statusCode}');
      }
    } catch (e) {

      rethrow;
    }
  }

  Future<PeriodHistory> savePeriodHistory(PeriodHistory periodHistory, {String? ownerId}) async {
    try {
      final periodJson = periodHistory.toJson();
      // Adicionar ownerId se fornecido
      if (ownerId != null) {
        periodJson['ownerId'] = ownerId;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/period-history'),
        headers: _getHeaders(),
        body: json.encode(periodJson),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to save period history');
      }
      
      final decoded = json.decode(response.body);
      return PeriodHistory.fromJson(decoded);
    } catch (e) {

      rethrow;
    }
  }

  Future<PeriodHistory> updatePeriodHistory(String id, String name) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/period-history/$id'),
        headers: _getHeaders(),
        body: json.encode({ 'name': name }),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update period history');
      }
      
      final decoded = json.decode(response.body);
      return PeriodHistory.fromJson(decoded);
    } catch (e) {

      rethrow;
    }
  }

  Future<void> deletePeriodHistory(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/period-history/$id'),
        headers: _getHeaders(),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to delete period history');
      }
    } catch (e) {

      rethrow;
    }
  }

  // Importar transações em bulk
  Future<Map<String, dynamic>> importBulkTransactions(
    List<Map<String, dynamic>> transactions, {
    required String walletId,
  }) async {
    try {
      // Adicionar walletId a todas as transações
      final transactionsWithWallet = transactions.map((tx) {
        tx['walletId'] = walletId;
        return tx;
      }).toList();
      
      // Incluir walletId no body principal para o middleware
      final response = await http.post(
        Uri.parse('$baseUrl/transactions/bulk?walletId=$walletId'),
        headers: _getHeaders(),
        body: json.encode({ 
          'transactions': transactionsWithWallet,
          'walletId': walletId, // Também no body para garantir
        }),
      );

      if (response.statusCode != 201) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to import transactions');
      }
      
      return json.decode(response.body);
    } catch (e) {

      rethrow;
    }
  }

  // Função isolada para parsing de transações
  static List<Transaction> _parseTransactions(String responseBody) {
    final List<dynamic> decoded = json.decode(responseBody);
    return decoded.map((json) => Transaction.fromJson(json)).toList();
  }
}
