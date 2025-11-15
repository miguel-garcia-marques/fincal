import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/budget_balances.dart';
import '../utils/date_utils.dart';
import '../utils/zeller_formula.dart';
import '../theme/app_theme.dart';
import '../screens/add_transaction_screen.dart';
import '../services/database.dart';

class DayDetailsDialog extends StatefulWidget {
  final DateTime date;
  final List<Transaction> transactions;
  final double availableBalance;
  final BudgetBalances? budgetBalances;
  final List<Transaction>? allPeriodTransactions;
  final DateTime? periodStartDate;
  final DateTime? periodEndDate;
  final String? walletId;
  final String? userId;
  final VoidCallback? onTransactionAdded;
  final VoidCallback? onTransactionDeleted;

  const DayDetailsDialog({
    super.key,
    required this.date,
    required this.transactions,
    required this.availableBalance,
    this.budgetBalances,
    this.allPeriodTransactions,
    this.periodStartDate,
    this.periodEndDate,
    this.walletId,
    this.userId,
    this.onTransactionAdded,
    this.onTransactionDeleted,
  });

  @override
  State<DayDetailsDialog> createState() => _DayDetailsDialogState();
}

class _DayDetailsDialogState extends State<DayDetailsDialog> {
  late List<Transaction> _localTransactions;

  @override
  void initState() {
    super.initState();
    _localTransactions = List.from(widget.transactions);
  }

  @override
  Widget build(BuildContext context) {
    final dayTransactions = _localTransactions.where((t) {
      final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
      return isSameDay(transactionDate, widget.date);
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

    final dayOfWeek = getDayOfWeek(widget.date);

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
                          formatDate(widget.date),
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
                          formatCurrency(widget.availableBalance),
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: widget.availableBalance >= 0
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
              if (widget.budgetBalances != null &&
                  (widget.budgetBalances!.gastos != 0 ||
                      widget.budgetBalances!.lazer != 0 ||
                      widget.budgetBalances!.poupanca != 0))
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
                      value: formatCurrency(widget.budgetBalances!.gastos),
                      color: widget.budgetBalances!.gastos >= 0
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                      categoryColor: AppTheme.expensesRed,
                      onTap: widget.allPeriodTransactions != null &&
                              widget.periodStartDate != null &&
                              widget.periodEndDate != null
                          ? () {
                              Navigator.of(context).pop();
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    CategoryTransactionsDialog(
                                  category: ExpenseBudgetCategory.gastos,
                                  transactions: widget.allPeriodTransactions!,
                                  startDate: widget.periodStartDate!,
                                  endDate: widget.periodEndDate!,
                                ),
                              );
                            }
                          : null,
                    ),
                    const SizedBox(height: 4),
                    _ClickableInfoCard(
                      title: 'Lazer',
                      value: formatCurrency(widget.budgetBalances!.lazer),
                      color: widget.budgetBalances!.lazer >= 0
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                      categoryColor: AppTheme.leisureBlue,
                      onTap: widget.allPeriodTransactions != null &&
                              widget.periodStartDate != null &&
                              widget.periodEndDate != null
                          ? () {
                              Navigator.of(context).pop();
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    CategoryTransactionsDialog(
                                  category: ExpenseBudgetCategory.lazer,
                                  transactions: widget.allPeriodTransactions!,
                                  startDate: widget.periodStartDate!,
                                  endDate: widget.periodEndDate!,
                                ),
                              );
                            }
                          : null,
                    ),
                    const SizedBox(height: 4),
                    _ClickableInfoCard(
                      title: 'Poupança',
                      value: formatCurrency(widget.budgetBalances!.poupanca),
                      color: widget.budgetBalances!.poupanca >= 0
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                      categoryColor: AppTheme.savingsYellow,
                      onTap: widget.allPeriodTransactions != null &&
                              widget.periodStartDate != null &&
                              widget.periodEndDate != null
                          ? () {
                              Navigator.of(context).pop();
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    CategoryTransactionsDialog(
                                  category: ExpenseBudgetCategory.poupanca,
                                  transactions: widget.allPeriodTransactions!,
                                  startDate: widget.periodStartDate!,
                                  endDate: widget.periodEndDate!,
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
                          if (widget.walletId != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              iconSize: 20,
                              color: AppTheme.expenseRed,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                String transactionIdToDelete = transaction.id;
                                final originalId = transaction.id;
                                if (transaction.id.contains('_')) {
                                  final parts = transaction.id.split('_');
                                  if (parts.length >= 2) {
                                    transactionIdToDelete =
                                        parts.sublist(0, parts.length - 1).join('_');
                                  }
                                }

                                final isPeriodic =
                                    transaction.frequency != TransactionFrequency.unique;
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Confirmar exclusão'),
                                    content: Text(
                                      isPeriodic
                                          ? 'Esta é uma transação periódica. Ao excluir, todas as ocorrências serão removidas. Tem certeza?'
                                          : 'Tem certeza que deseja excluir esta transação?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text('Cancelar'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.expenseRed,
                                        ),
                                        child: const Text('Excluir'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed == true) {
                                  // Remover imediatamente da UI (otimista)
                                  setState(() {
                                    if (isPeriodic) {
                                      // Se for periódica, remover todas as ocorrências
                                      _localTransactions.removeWhere((t) {
                                        String tId = t.id;
                                        if (t.id.contains('_')) {
                                          final parts = t.id.split('_');
                                          if (parts.length >= 2) {
                                            tId = parts.sublist(0, parts.length - 1).join('_');
                                          }
                                        }
                                        return tId == transactionIdToDelete;
                                      });
                                    } else {
                                      // Se for única, remover apenas esta
                                      _localTransactions.removeWhere((t) => t.id == originalId);
                                    }
                                  });

                                  try {
                                    await DatabaseService().deleteTransaction(
                                      transactionIdToDelete,
                                      walletId: widget.walletId!,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Transação excluída com sucesso'),
                                        ),
                                      );
                                      if (widget.onTransactionDeleted != null) {
                                        widget.onTransactionDeleted!();
                                      }
                                    }
                                  } catch (e) {
                                    // Reverter a mudança em caso de erro
                                    if (context.mounted) {
                                      setState(() {
                                        _localTransactions = List.from(widget.transactions);
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Erro ao excluir: $e'),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 12),
              if (widget.walletId != null && widget.userId != null) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Abrir tela de adicionar transação com a data pré-selecionada
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      isDismissible: true,
                      enableDrag: true,
                      builder: (context) => AddTransactionScreen(
                        walletId: widget.walletId!,
                        userId: widget.userId!,
                        initialDate: widget.date,
                        skipImportOption: true,
                      ),
                    ).then((result) {
                      if (result == true && widget.onTransactionAdded != null) {
                        widget.onTransactionAdded!();
                      }
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar Transação'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.black,
                    foregroundColor: AppTheme.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
