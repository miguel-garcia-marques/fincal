import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';
import '../models/period_history.dart';
import 'auth_service.dart';

class ApiService {
  final AuthService _authService = AuthService();

  // Configurar a URL base da API
  // Para desenvolvimento local: 'http://localhost:3000'
  // Para produção: usar o URL do servidor
  static const String baseUrl = 'http://localhost:3000/api';
  
  // Se estiver a usar um dispositivo físico/emulador, pode precisar de:
  // Android Emulator: 'http://10.0.2.2:3000/api'
  // iOS Simulator: 'http://localhost:3000/api'
  // Dispositivo físico: 'http://SEU_IP_LOCAL:3000/api'

  // Obter headers com autenticação
  Map<String, String> _getHeaders() {
    final token = _authService.currentAccessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<Transaction>> getAllTransactions() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/transactions'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => Transaction.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load transactions: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching transactions: $e');
      return [];
    }
  }

  Future<void> saveTransaction(Transaction transaction) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/transactions'),
        headers: _getHeaders(),
        body: json.encode(transaction.toJson()),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to save transaction');
      }
    } catch (e) {
      print('Error saving transaction: $e');
      rethrow;
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/transactions/${transaction.id}'),
        headers: _getHeaders(),
        body: json.encode(transaction.toJson()),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update transaction');
      }
    } catch (e) {
      print('Error updating transaction: $e');
      rethrow;
    }
  }

  Future<void> deleteTransaction(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/transactions/$id'),
        headers: _getHeaders(),
      );

      if (response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to delete transaction');
      }
    } catch (e) {
      print('Error deleting transaction: $e');
      rethrow;
    }
  }

  Future<List<Transaction>> getTransactionsInRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final startStr = _formatDateForApi(startDate);
      final endStr = _formatDateForApi(endDate);
      
      final response = await http.get(
        Uri.parse('$baseUrl/transactions/range?startDate=$startStr&endDate=$endStr'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => Transaction.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load transactions: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching transactions in range: $e');
      return [];
    }
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Period History methods
  Future<List<PeriodHistory>> getAllPeriodHistories() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/period-history'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        return decoded.map((json) => PeriodHistory.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load period histories: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching period histories: $e');
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
      print('Error fetching period history: $e');
      rethrow;
    }
  }

  Future<PeriodHistory> savePeriodHistory(PeriodHistory periodHistory) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/period-history'),
        headers: _getHeaders(),
        body: json.encode(periodHistory.toJson()),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to save period history');
      }
      
      final decoded = json.decode(response.body);
      return PeriodHistory.fromJson(decoded);
    } catch (e) {
      print('Error saving period history: $e');
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
      print('Error deleting period history: $e');
      rethrow;
    }
  }
}

