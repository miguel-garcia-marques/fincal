import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';
import '../utils/zeller_formula.dart';
import '../utils/date_utils.dart';
import 'api_service.dart';

class DatabaseService {
  // Mudar para true para usar MongoDB via API
  static const bool useApi = true;
  
  final ApiService _apiService = ApiService();
  static const String _transactionsKey = 'transactions';

  // Método privado para SharedPreferences (fallback)
  Future<List<Transaction>> _getAllTransactionsLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final transactionsJson = prefs.getString(_transactionsKey);
      
      if (transactionsJson == null) {
        return [];
      }

      final List<dynamic> decoded = json.decode(transactionsJson);
      return decoded.map((json) => Transaction.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveTransactionLocal(Transaction transaction) async {
    final transactions = await _getAllTransactionsLocal();
    transactions.add(transaction);
    await _saveTransactionsLocal(transactions);
  }

  Future<void> _saveTransactionsLocal(List<Transaction> transactions) async {
    final prefs = await SharedPreferences.getInstance();
    final transactionsJson = json.encode(
      transactions.map((t) => t.toJson()).toList(),
    );
    await prefs.setString(_transactionsKey, transactionsJson);
  }

  Future<List<Transaction>> getAllTransactions() async {
    if (useApi) {
      return await _apiService.getAllTransactions();
    } else {
      return await _getAllTransactionsLocal();
    }
  }

  Future<void> saveTransaction(Transaction transaction) async {
    if (useApi) {
      await _apiService.saveTransaction(transaction);
    } else {
      await _saveTransactionLocal(transaction);
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    if (useApi) {
      await _apiService.updateTransaction(transaction);
    } else {
      final transactions = await _getAllTransactionsLocal();
      final index = transactions.indexWhere((t) => t.id == transaction.id);
      if (index != -1) {
        transactions[index] = transaction;
        await _saveTransactionsLocal(transactions);
      }
    }
  }

  Future<void> deleteTransaction(String id) async {
    if (useApi) {
      await _apiService.deleteTransaction(id);
    } else {
      final transactions = await _getAllTransactionsLocal();
      transactions.removeWhere((t) => t.id == id);
      await _saveTransactionsLocal(transactions);
    }
  }

  Future<List<Transaction>> getTransactionsInRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (useApi) {
      return await _apiService.getTransactionsInRange(startDate, endDate);
    } else {
      // Lógica local (mantida para compatibilidade)
      final allTransactions = await _getAllTransactionsLocal();
      final List<Transaction> result = [];
      
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      
      for (var transaction in allTransactions) {
        if (transaction.frequency == TransactionFrequency.unique) {
          final transactionDate = DateTime(
            transaction.date.year,
            transaction.date.month,
            transaction.date.day,
          );
          
          if ((transactionDate.isAfter(start) || transactionDate.isAtSameMomentAs(start)) &&
              (transactionDate.isBefore(end) || transactionDate.isAtSameMomentAs(end))) {
            result.add(transaction);
          }
        } else if (transaction.frequency == TransactionFrequency.weekly) {
          if (transaction.dayOfWeek == null) continue;
          
          DateTime currentDate = start;
          while (currentDate.isBefore(end) || currentDate.isAtSameMomentAs(end)) {
            final zellerDayOfWeek = getDayOfWeek(currentDate);
            final formDayOfWeek = (zellerDayOfWeek == 0) ? 0 : zellerDayOfWeek;
            
            if (formDayOfWeek == transaction.dayOfWeek) {
              result.add(Transaction(
                id: '${transaction.id}_${currentDate.millisecondsSinceEpoch}',
                type: transaction.type,
                date: currentDate,
                description: transaction.description,
                amount: transaction.amount,
                category: transaction.category,
                isSalary: transaction.isSalary,
                salaryAllocation: transaction.salaryAllocation,
                expenseBudgetCategory: transaction.expenseBudgetCategory,
                frequency: TransactionFrequency.weekly, // Manter informação de periodicidade
                dayOfWeek: transaction.dayOfWeek, // Manter informação do dia
                dayOfMonth: null,
              ));
            }
            currentDate = currentDate.add(const Duration(days: 1));
          }
        } else if (transaction.frequency == TransactionFrequency.monthly) {
          if (transaction.dayOfMonth == null) continue;
          
          DateTime currentDate = start;
          while (currentDate.isBefore(end) || currentDate.isAtSameMomentAs(end)) {
            if (currentDate.day == transaction.dayOfMonth) {
              result.add(Transaction(
                id: '${transaction.id}_${currentDate.millisecondsSinceEpoch}',
                type: transaction.type,
                date: currentDate,
                description: transaction.description,
                amount: transaction.amount,
                category: transaction.category,
                isSalary: transaction.isSalary,
                salaryAllocation: transaction.salaryAllocation,
                expenseBudgetCategory: transaction.expenseBudgetCategory,
                frequency: TransactionFrequency.monthly, // Manter informação de periodicidade
                dayOfWeek: null,
                dayOfMonth: transaction.dayOfMonth, // Manter informação do dia
              ));
            }
            currentDate = currentDate.add(const Duration(days: 1));
          }
        }
      }
      
      result.sort((a, b) => a.date.compareTo(b.date));
      return result;
    }
  }
  
  // Calcular saldos separados por categoria
  Future<Map<String, double>> calculateBudgetBalances(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final transactions = await getTransactionsInRange(startDate, endDate);
    
    double gastos = 0.0;
    double lazer = 0.0;
    double poupanca = 0.0;
    
    for (var transaction in transactions) {
      if (transaction.type == TransactionType.ganho && transaction.isSalary) {
        final values = transaction.salaryValues;
        if (values != null) {
          gastos += values.gastos;
          lazer += values.lazer;
          poupanca += values.poupanca;
        }
      } else if (transaction.type == TransactionType.despesa) {
        final amount = transaction.amount;
        switch (transaction.expenseBudgetCategory) {
          case ExpenseBudgetCategory.gastos:
            gastos -= amount;
            break;
          case ExpenseBudgetCategory.lazer:
            lazer -= amount;
            break;
          case ExpenseBudgetCategory.poupanca:
            poupanca -= amount;
            break;
          case null:
            break;
        }
      }
    }
    
    return {
      'gastos': gastos,
      'lazer': lazer,
      'poupanca': poupanca,
    };
  }
}
