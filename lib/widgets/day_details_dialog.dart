import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/budget_balances.dart';
import '../utils/date_utils.dart';
import '../utils/zeller_formula.dart';
import '../theme/app_theme.dart';

class DayDetailsDialog extends StatelessWidget {
  final DateTime date;
  final List<Transaction> transactions;
  final double availableBalance;
  final BudgetBalances? budgetBalances;

  const DayDetailsDialog({
    super.key,
    required this.date,
    required this.transactions,
    required this.availableBalance,
    this.budgetBalances,
  });

  @override
  Widget build(BuildContext context) {
    final dayTransactions = transactions.where((t) {
      final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
      return isSameDay(transactionDate, date);
    }).toList();

    final expenses = dayTransactions
        .where((t) => t.type == TransactionType.despesa)
        .toList();
    final gains = dayTransactions
        .where((t) => t.type == TransactionType.ganho)
        .toList();

    final totalExpenses = expenses.fold<double>(
      0.0,
      (sum, t) => sum + t.amount,
    );
    final totalGains = gains.fold<double>(
      0.0,
      (sum, t) => sum + t.amount,
    );

    final dayOfWeek = getDayOfWeek(date);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDate(date),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        getDayNameFull(dayOfWeek),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.lighterGray.withOpacity(0.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Saldo disponível
            _InfoCard(
              title: 'Saldo Disponível',
              value: formatCurrency(availableBalance),
              color: availableBalance >= 0 
                  ? AppTheme.incomeGreen 
                  : AppTheme.expenseRed,
            ),
            const SizedBox(height: 8),
            
            // Valores separados por categoria (se existirem)
            if (budgetBalances != null && (budgetBalances!.gastos != 0 || budgetBalances!.lazer != 0 || budgetBalances!.poupanca != 0)) ...[
              Text(
                'Orçamento Disponível',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _InfoCard(
                title: 'Gastos',
                value: formatCurrency(budgetBalances!.gastos),
                color: budgetBalances!.gastos >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
              ),
              const SizedBox(height: 4),
              _InfoCard(
                title: 'Lazer',
                value: formatCurrency(budgetBalances!.lazer),
                color: budgetBalances!.lazer >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
              ),
              const SizedBox(height: 4),
              _InfoCard(
                title: 'Poupança',
                value: formatCurrency(budgetBalances!.poupanca),
                color: budgetBalances!.poupanca >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
              ),
              const SizedBox(height: 8),
            ],
            
            // Ganhos do dia
            if (totalGains > 0)
              _InfoCard(
                title: 'Ganhos do Dia',
                value: formatCurrency(totalGains),
                color: AppTheme.incomeGreen,
              ),
            if (totalGains > 0) const SizedBox(height: 8),
            
            // Despesas do dia
            if (totalExpenses > 0)
              _InfoCard(
                title: 'Despesas do Dia',
                value: formatCurrency(totalExpenses),
                color: AppTheme.expenseRed,
              ),
            if (totalExpenses > 0) const SizedBox(height: 12),
            
            // Lista de transações
            if (dayTransactions.isNotEmpty) ...[
              Text(
                'Transações',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...dayTransactions.map((transaction) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.lighterGray.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: transaction.type == TransactionType.ganho
                                ? AppTheme.incomeGreen.withOpacity(0.2)
                                : AppTheme.expenseRed.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            transaction.type == TransactionType.ganho
                                ? 'Ganho'
                                : 'Despesa',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: transaction.type == TransactionType.ganho
                                  ? AppTheme.incomeGreen
                                  : AppTheme.expenseRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                transaction.category.displayName,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (transaction.description != null &&
                                  transaction.description!.isNotEmpty)
                                Text(
                                  transaction.description!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.darkGray,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          formatCurrency(transaction.amount),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: transaction.type == TransactionType.ganho
                                ? AppTheme.incomeGreen
                                : AppTheme.expenseRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

