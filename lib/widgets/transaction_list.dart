import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/date_utils.dart';
import '../utils/zeller_formula.dart';
import '../theme/app_theme.dart';
import '../services/database.dart';
import 'add_transaction_dialog.dart';

class TransactionListWidget extends StatelessWidget {
  final List<Transaction> transactions;
  final Function()? onTransactionUpdated;

  const TransactionListWidget({
    super.key,
    required this.transactions,
    this.onTransactionUpdated,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Center(
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
          'Nenhuma transação neste período',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppTheme.darkGray,
          ),
            ),
          ],
        ),
      );
    }

    // Agrupar transações por data
    final groupedTransactions = <DateTime, List<Transaction>>{};
    for (var transaction in transactions) {
      final date = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      if (!groupedTransactions.containsKey(date)) {
        groupedTransactions[date] = [];
      }
      groupedTransactions[date]!.add(transaction);
    }

    // Ordenar datas (mais recente primeiro)
    final sortedDates = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long,
                  color: AppTheme.black,
                  size: 24,
                ),
      ),
              const SizedBox(width: 12),
              Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transações',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
                    Text(
                      '${transactions.length} ${transactions.length == 1 ? 'transação' : 'transações'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: sortedDates.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final date = sortedDates[index];
                final dateTransactions = groupedTransactions[date]!;
                
                // Calcular total do dia
                double dayTotal = 0.0;
                for (var t in dateTransactions) {
                  if (t.type == TransactionType.ganho) {
                    dayTotal += t.amount;
                  } else {
                    dayTotal -= t.amount;
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho da data
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            formatDate(date),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.black,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: dayTotal >= 0
                                  ? AppTheme.incomeGreen.withOpacity(0.1)
                                  : AppTheme.expenseRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              formatCurrency(dayTotal.abs()),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: dayTotal >= 0
                                    ? AppTheme.incomeGreen
                                    : AppTheme.expenseRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Lista de transações do dia
                    ...dateTransactions.map((transaction) => _TransactionCard(
                  transaction: transaction,
                  onEdit: () async {
                    Transaction? transactionToEdit = transaction;
                    
                    if (transaction.id.contains('_') && 
                        (transaction.frequency == TransactionFrequency.weekly || 
                         transaction.frequency == TransactionFrequency.monthly)) {
                      try {
                        final dbService = DatabaseService();
                        final parts = transaction.id.split('_');
                        if (parts.length >= 2) {
                          final originalId = parts.sublist(0, parts.length - 1).join('_');
                          final allTransactions = await dbService.getAllTransactions();
                          transactionToEdit = allTransactions.firstWhere(
                            (t) => t.id == originalId,
                            orElse: () => transaction,
                          );
                        }
                      } catch (e) {
                        transactionToEdit = transaction;
                      }
                    }
                    
                    final result = await showDialog(
                      context: context,
                      builder: (context) => AddTransactionDialog(
                        transactionToEdit: transactionToEdit,
                      ),
                    );
                    if (result == true && onTransactionUpdated != null) {
                      onTransactionUpdated!();
                    }
                  },
                  onDelete: () async {
                    String transactionIdToDelete = transaction.id;
                    if (transaction.id.contains('_')) {
                      final parts = transaction.id.split('_');
                      if (parts.length >= 2) {
                        transactionIdToDelete = parts.sublist(0, parts.length - 1).join('_');
                      }
                    }
                    
                    final isPeriodic = transaction.frequency != TransactionFrequency.unique;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirmar exclusão'),
                        content: Text(
                          isPeriodic 
                            ? 'Esta é uma transação periódica. Ao excluir, todas as ocorrências serão removidas. Tem certeza?'
                            : 'Tem certeza que deseja excluir esta transação?'
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
                      try {
                        await DatabaseService().deleteTransaction(transactionIdToDelete);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Transação excluída com sucesso')),
                          );
                        }
                        if (onTransactionUpdated != null) {
                          onTransactionUpdated!();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro ao excluir: $e')),
                          );
                        }
                      }
                    }
                  },
                    )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _TransactionCard({
    required this.transaction,
    this.onEdit,
    this.onDelete,
  });

  String _getPeriodicityText(Transaction transaction) {
    if (transaction.frequency == TransactionFrequency.weekly && transaction.dayOfWeek != null) {
      final dayName = getDayNameFull(transaction.dayOfWeek!);
      return '${transaction.frequency.displayName} - $dayName';
    } else if (transaction.frequency == TransactionFrequency.monthly && transaction.dayOfMonth != null) {
      return '${transaction.frequency.displayName} - Dia ${transaction.dayOfMonth}';
    }
    return transaction.frequency.displayName;
  }

  IconData _getCategoryIcon(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.compras:
        return Icons.shopping_cart;
      case TransactionCategory.cafe:
        return Icons.local_cafe;
      case TransactionCategory.combustivel:
        return Icons.local_gas_station;
      case TransactionCategory.subscricao:
        return Icons.subscriptions;
      case TransactionCategory.dizimo:
        return Icons.church;
      case TransactionCategory.carro:
        return Icons.directions_car;
      case TransactionCategory.multibanco:
        return Icons.atm;
      case TransactionCategory.saude:
        return Icons.local_hospital;
      case TransactionCategory.comerFora:
        return Icons.restaurant;
      case TransactionCategory.miscelaneos:
        return Icons.category;
      case TransactionCategory.prendas:
        return Icons.card_giftcard;
      case TransactionCategory.extras:
        return Icons.star;
      case TransactionCategory.snacks:
        return Icons.fastfood;
      case TransactionCategory.comprasOnline:
        return Icons.shopping_bag;
      case TransactionCategory.comprasRoupa:
        return Icons.checkroom;
      case TransactionCategory.animais:
        return Icons.pets;
      // Categorias de ganhos
      case TransactionCategory.salario:
        return Icons.account_balance_wallet;
      case TransactionCategory.alimentacao:
        return Icons.restaurant_menu;
      case TransactionCategory.outro:
        return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGanho = transaction.type == TransactionType.ganho;
    final categoryIcon = transaction.isSalary
        ? Icons.account_balance_wallet
        : _getCategoryIcon(transaction.category);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isGanho
            ? AppTheme.incomeGreen.withOpacity(0.05)
            : AppTheme.expenseRed.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGanho
              ? AppTheme.incomeGreen.withOpacity(0.2)
              : AppTheme.expenseRed.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Ícone da categoria
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isGanho 
                  ? AppTheme.incomeGreen.withOpacity(0.15)
                  : AppTheme.expenseRed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              categoryIcon,
                color: isGanho ? AppTheme.incomeGreen : AppTheme.expenseRed,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          // Informações da transação
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                      transaction.category.displayName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.black,
                    ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                      const SizedBox(width: 8),
                    // Badge de periodicidade
                    if (transaction.frequency != TransactionFrequency.unique)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.black.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getPeriodicityText(transaction),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                ),
                if (transaction.description != null && transaction.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    transaction.description!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.darkGray,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Informações adicionais
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Badge de tipo
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isGanho
                            ? AppTheme.incomeGreen.withOpacity(0.2)
                            : AppTheme.expenseRed.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    child: Text(
                        isGanho ? 'Ganho' : 'Despesa',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isGanho ? AppTheme.incomeGreen : AppTheme.expenseRed,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    // Badge de orçamento (se aplicável)
                    if (transaction.expenseBudgetCategory != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                      ),
                        decoration: BoxDecoration(
                          color: AppTheme.black.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          transaction.expenseBudgetCategory!.displayName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.black,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                    // Badge de salário (se aplicável)
                    if (transaction.isSalary) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.incomeGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.attach_money,
                              size: 12,
                              color: AppTheme.incomeGreen,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Salário',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.incomeGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Valor e ações
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
          Text(
            formatCurrency(transaction.amount),
                style: AppTheme.monospaceTextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
              color: isGanho ? AppTheme.incomeGreen : AppTheme.expenseRed,
            ),
          ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 18,
            color: AppTheme.black,
                        ),
                      ),
                    ),
          ),
          const SizedBox(width: 4),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
            color: AppTheme.expenseRed,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
