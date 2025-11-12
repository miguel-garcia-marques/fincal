import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/date_utils.dart';
import '../utils/zeller_formula.dart';
import '../theme/app_theme.dart';
import '../services/database.dart';
import 'add_transaction_screen.dart';

class TransactionDetailsScreen extends StatelessWidget {
  final Transaction transaction;
  final String walletId;
  final String userId;
  final String walletPermission; // 'owner', 'read', 'write'

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
    required this.walletId,
    required this.userId,
    required this.walletPermission,
  });

  String _getPeriodicityText(Transaction transaction) {
    if (transaction.frequency == TransactionFrequency.weekly &&
        transaction.dayOfWeek != null) {
      final dayName = getDayNameFull(transaction.dayOfWeek!);
      return '${transaction.frequency.displayName} - $dayName';
    } else if (transaction.frequency == TransactionFrequency.monthly &&
        transaction.dayOfMonth != null) {
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
      case TransactionCategory.comunicacoes:
        return Icons.phone;
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

    return Scaffold(
      backgroundColor: AppTheme.white,
      appBar: AppBar(
        backgroundColor: AppTheme.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Detalhes da Transação',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.black,
              ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: AppTheme.black),
            onPressed: () async {
              // Verificar permissão antes de editar
              if (walletPermission == 'read') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Você só tem permissão para visualizar este calendário'),
                    duration: Duration(seconds: 3),
                  ),
                );
                return;
              }

              Transaction? transactionToEdit = transaction;

              if (transaction.id.contains('_') &&
                  (transaction.frequency == TransactionFrequency.weekly ||
                      transaction.frequency ==
                          TransactionFrequency.monthly)) {
                try {
                  final dbService = DatabaseService();
                  final parts = transaction.id.split('_');
                  if (parts.length >= 2) {
                    final originalId =
                        parts.sublist(0, parts.length - 1).join('_');
                    final allTransactions =
                        await dbService.getAllTransactions(walletId: walletId);
                    transactionToEdit = allTransactions.firstWhere(
                      (t) => t.id == originalId,
                      orElse: () => transaction,
                    );
                  }
                } catch (e) {
                  transactionToEdit = transaction;
                }
              }

              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AddTransactionScreen(
                    transactionToEdit: transactionToEdit,
                    walletId: walletId,
                    userId: userId,
                  ),
                  fullscreenDialog: true,
                ),
              );

              if (result == true && context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card principal
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isGanho
                    ? AppTheme.incomeGreen.withOpacity(0.05)
                    : AppTheme.expenseRed.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isGanho
                      ? AppTheme.incomeGreen.withOpacity(0.2)
                      : AppTheme.expenseRed.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // Ícone da categoria
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isGanho
                          ? AppTheme.incomeGreen.withOpacity(0.15)
                          : AppTheme.expenseRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      categoryIcon,
                      color: isGanho ? AppTheme.incomeGreen : AppTheme.expenseRed,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Valor
                  Text(
                    formatCurrency(transaction.amount),
                    style: AppTheme.monospaceTextStyle(
                      context: context,
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: isGanho ? AppTheme.incomeGreen : AppTheme.expenseRed,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tipo
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isGanho
                          ? AppTheme.incomeGreen.withOpacity(0.2)
                          : AppTheme.expenseRed.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isGanho ? 'Ganho' : 'Despesa',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isGanho
                                ? AppTheme.incomeGreen
                                : AppTheme.expenseRed,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Informações detalhadas
            _DetailSection(
              title: 'Informações',
              children: [
                _DetailRow(
                  label: 'Categoria',
                  value: transaction.category.displayName,
                ),
                if (transaction.description != null &&
                    transaction.description!.isNotEmpty)
                  _DetailRow(
                    label: 'Descrição',
                    value: transaction.description!,
                  ),
                _DetailRow(
                  label: 'Data',
                  value: formatDate(transaction.date),
                ),
                if (transaction.frequency != TransactionFrequency.unique)
                  _DetailRow(
                    label: 'Periodicidade',
                    value: _getPeriodicityText(transaction),
                  ),
              ],
            ),
            if (transaction.isSalary ||
                transaction.expenseBudgetCategory != null) ...[
              const SizedBox(height: 24),
              _DetailSection(
                title: 'Orçamento',
                children: [
                  if (transaction.isSalary && transaction.salaryValues != null) ...[
                    _DetailRow(
                      label: 'Gastos',
                      value: formatCurrency(transaction.salaryValues!.gastos),
                    ),
                    _DetailRow(
                      label: 'Lazer',
                      value: formatCurrency(transaction.salaryValues!.lazer),
                    ),
                    _DetailRow(
                      label: 'Poupança',
                      value: formatCurrency(transaction.salaryValues!.poupanca),
                    ),
                    if (transaction.salaryAllocation != null) ...[
                      _DetailRow(
                        label: 'Gastos %',
                        value: '${transaction.salaryAllocation!.gastosPercent.toStringAsFixed(1)}%',
                      ),
                      _DetailRow(
                        label: 'Lazer %',
                        value: '${transaction.salaryAllocation!.lazerPercent.toStringAsFixed(1)}%',
                      ),
                      _DetailRow(
                        label: 'Poupança %',
                        value: '${transaction.salaryAllocation!.poupancaPercent.toStringAsFixed(1)}%',
                      ),
                    ],
                  ],
                  if (transaction.expenseBudgetCategory != null)
                    _DetailRow(
                      label: 'Categoria',
                      value: transaction.expenseBudgetCategory!.displayName,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            // Botão de excluir
            OutlinedButton(
              onPressed: () async {
                String transactionIdToDelete = transaction.id;
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
                  try {
                    await DatabaseService()
                        .deleteTransaction(transactionIdToDelete, walletId: walletId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Transação excluída com sucesso')),
                      );
                      Navigator.of(context).pop(true);
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
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.expenseRed,
                side: const BorderSide(color: AppTheme.expenseRed),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Excluir Transação'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.offWhite,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.darkGray,
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.black,
                  ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
