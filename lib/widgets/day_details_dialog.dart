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
  final List<Transaction>? allPeriodTransactions;
  final DateTime? periodStartDate;
  final DateTime? periodEndDate;

  const DayDetailsDialog({
    super.key,
    required this.date,
    required this.transactions,
    required this.availableBalance,
    this.budgetBalances,
    this.allPeriodTransactions,
    this.periodStartDate,
    this.periodEndDate,
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
    final gains =
        dayTransactions.where((t) => t.type == TransactionType.ganho).toList();

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
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
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
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
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

              // Saldo disponível e Despesas do dia no mesmo card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lighterGray.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Saldo Disponível',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        Text(
                          formatCurrency(availableBalance),
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: availableBalance >= 0
                                        ? AppTheme.incomeGreen
                                        : AppTheme.expenseRed,
                                  ),
                        ),
                      ],
                    ),
                    if (totalExpenses > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Despesas do Dia',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            formatCurrency(totalExpenses),
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.expenseRed,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Valores separados por categoria (se existirem) - Seção expansível
              if (budgetBalances != null &&
                  (budgetBalances!.gastos != 0 ||
                      budgetBalances!.lazer != 0 ||
                      budgetBalances!.poupanca != 0))
                ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
                  title: Text(
                    'Orçamento Disponível',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  children: [
                    _ClickableInfoCard(
                      title: 'Gastos',
                      value: formatCurrency(budgetBalances!.gastos),
                      color: budgetBalances!.gastos >= 0
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                      categoryColor: AppTheme.expensesRed,
                      onTap: allPeriodTransactions != null &&
                              periodStartDate != null &&
                              periodEndDate != null
                          ? () {
                              Navigator.of(context).pop();
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    CategoryTransactionsDialog(
                                  category: ExpenseBudgetCategory.gastos,
                                  transactions: allPeriodTransactions!,
                                  startDate: periodStartDate!,
                                  endDate: periodEndDate!,
                                ),
                              );
                            }
                          : null,
                    ),
                    const SizedBox(height: 4),
                    _ClickableInfoCard(
                      title: 'Lazer',
                      value: formatCurrency(budgetBalances!.lazer),
                      color: budgetBalances!.lazer >= 0
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                      categoryColor: AppTheme.leisureBlue,
                      onTap: allPeriodTransactions != null &&
                              periodStartDate != null &&
                              periodEndDate != null
                          ? () {
                              Navigator.of(context).pop();
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    CategoryTransactionsDialog(
                                  category: ExpenseBudgetCategory.lazer,
                                  transactions: allPeriodTransactions!,
                                  startDate: periodStartDate!,
                                  endDate: periodEndDate!,
                                ),
                              );
                            }
                          : null,
                    ),
                    const SizedBox(height: 4),
                    _ClickableInfoCard(
                      title: 'Poupança',
                      value: formatCurrency(budgetBalances!.poupanca),
                      color: budgetBalances!.poupanca >= 0
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                      categoryColor: AppTheme.savingsYellow,
                      onTap: allPeriodTransactions != null &&
                              periodStartDate != null &&
                              periodEndDate != null
                          ? () {
                              Navigator.of(context).pop();
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    CategoryTransactionsDialog(
                                  category: ExpenseBudgetCategory.poupanca,
                                  transactions: allPeriodTransactions!,
                                  startDate: periodStartDate!,
                                  endDate: periodEndDate!,
                                ),
                              );
                            }
                          : null,
                    ),
                  ],
                ),

              // Ganhos do dia
              if (totalGains > 0) ...[
                const SizedBox(height: 8),
                _InfoCard(
                  title: 'Ganhos do Dia',
                  value: formatCurrency(totalGains),
                  color: AppTheme.incomeGreen,
                ),
              ],
              const SizedBox(height: 12),

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
                        color: AppTheme.lighterGray.withOpacity(0.1),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: transaction.type ==
                                            TransactionType.ganho
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                if (transaction.description != null &&
                                    transaction.description!.isNotEmpty)
                                  Text(
                                    transaction.description!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppTheme.darkGray,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            formatCurrency(transaction.amount),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      transaction.type == TransactionType.ganho
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
        color: AppTheme.lighterGray.withOpacity(0.1),
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

class _ClickableInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Color categoryColor;
  final VoidCallback? onTap;

  const _ClickableInfoCard({
    required this.title,
    required this.value,
    required this.color,
    required this.categoryColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: AppTheme.darkGray,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }

    return card;
  }
}

class CategoryTransactionsDialog extends StatelessWidget {
  final ExpenseBudgetCategory category;
  final List<Transaction> transactions;
  final DateTime startDate;
  final DateTime endDate;

  const CategoryTransactionsDialog({
    super.key,
    required this.category,
    required this.transactions,
    required this.startDate,
    required this.endDate,
  });

  Color _getCategoryColor() {
    switch (category) {
      case ExpenseBudgetCategory.gastos:
        return AppTheme.expensesRed;
      case ExpenseBudgetCategory.lazer:
        return AppTheme.leisureBlue;
      case ExpenseBudgetCategory.poupanca:
        return AppTheme.savingsYellow;
    }
  }

  String _getCategoryName() {
    return category.displayName;
  }

  List<Transaction> _getFilteredTransactions() {
    return transactions.where((t) {
      // Verificar se a transação está no período
      final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);

      if (transactionDate.isBefore(start) || transactionDate.isAfter(end)) {
        return false;
      }

      // Apenas despesas podem aparecer quando filtramos por categoria de orçamento
      // Ganhos não devem aparecer na lista de gastos
      if (t.type == TransactionType.despesa) {
        return t.expenseBudgetCategory == category;
      }

      return false;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // Mais recente primeiro
  }

  // Calcular ganhos que entram nesta categoria
  double _calculateGains() {
    double gains = 0.0;
    
    for (var transaction in transactions) {
      // Verificar se a transação está no período
      final transactionDate = DateTime(transaction.date.year, transaction.date.month, transaction.date.day);
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);

      if (transactionDate.isBefore(start) || transactionDate.isAfter(end)) {
        continue;
      }

      if (transaction.type == TransactionType.ganho) {
        if (transaction.isSalary && transaction.salaryValues != null) {
          // Salários: adicionar a parte alocada para esta categoria
          final values = transaction.salaryValues!;
          switch (category) {
            case ExpenseBudgetCategory.gastos:
              gains += values.gastos;
              break;
            case ExpenseBudgetCategory.lazer:
              gains += values.lazer;
              break;
            case ExpenseBudgetCategory.poupanca:
              // Poupança não é ganho, é despesa
              break;
          }
        } else if (transaction.category == TransactionCategory.alimentacao && 
                   category == ExpenseBudgetCategory.gastos) {
          // Ganhos de alimentação entram em "gastos"
          gains += transaction.amount;
        }
      }
    }
    
    return gains;
  }

  // Calcular despesas desta categoria
  double _calculateExpenses() {
    double expenses = 0.0;
    
    for (var transaction in transactions) {
      // Verificar se a transação está no período
      final transactionDate = DateTime(transaction.date.year, transaction.date.month, transaction.date.day);
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);

      if (transactionDate.isBefore(start) || transactionDate.isAfter(end)) {
        continue;
      }

      if (transaction.type == TransactionType.despesa && 
          transaction.expenseBudgetCategory == category) {
        expenses += transaction.amount;
      }
    }
    
    return expenses;
  }

  @override
  Widget build(BuildContext context) {
    final filteredTransactions = _getFilteredTransactions();
    final categoryColor = _getCategoryColor();
    final categoryName = _getCategoryName();
    final gains = _calculateGains();
    final expenses = _calculateExpenses();
    final balance = gains - expenses;

    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: categoryColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryName,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Text(
                            '${formatDate(startDate)} - ${formatDate(endDate)}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.darkGray,
                                    ),
                          ),
                        ],
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
            // Resumo: Ganhos e Despesas
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lighterGray.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ganhos',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        formatCurrency(gains),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.incomeGreen,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Despesas',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        formatCurrency(expenses),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.expenseRed,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: AppTheme.lighterGray.withOpacity(0.3),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saldo',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        formatCurrency(balance),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: balance >= 0
                                  ? AppTheme.incomeGreen
                                  : AppTheme.expenseRed,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${filteredTransactions.length} transação(ões)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.darkGray,
                  ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: filteredTransactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: AppTheme.lighterGray,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma transação encontrada',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: AppTheme.darkGray,
                                    ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredTransactions.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 1,
                        color: AppTheme.lighterGray.withOpacity(0.3),
                      ),
                      itemBuilder: (context, index) {
                        final transaction = filteredTransactions[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: categoryColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      transaction.description != null &&
                                              transaction
                                                  .description!.isNotEmpty
                                          ? transaction.description!
                                          : transaction.category.displayName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatDate(transaction.date),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.darkGray,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatCurrency(transaction.amount),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.black,
                                    ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
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
