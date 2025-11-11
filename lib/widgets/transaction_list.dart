import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';
import '../services/database.dart';
import 'add_transaction_dialog.dart';
import '../screens/transaction_details_screen.dart';

class TransactionListWidget extends StatefulWidget {
  final List<Transaction> transactions;
  final Function()? onTransactionUpdated;

  const TransactionListWidget({
    super.key,
    required this.transactions,
    this.onTransactionUpdated,
  });

  @override
  State<TransactionListWidget> createState() => _TransactionListWidgetState();
}

class _TransactionListWidgetState extends State<TransactionListWidget> {
  bool _showOnlyPeriodic = false;
  String? _selectedPerson;
  ExpenseBudgetCategory? _selectedBudgetCategory;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Transaction> get _filteredTransactions {
    var filtered = widget.transactions;
    
    // Filtro de busca por nome/descrição
    if (_searchController.text.isNotEmpty) {
      final searchQuery = _searchController.text.toLowerCase();
      filtered = filtered.where((t) {
        // Buscar na descrição
        if (t.description != null && t.description!.isNotEmpty) {
          if (t.description!.toLowerCase().contains(searchQuery)) {
            return true;
          }
        }
        // Buscar no nome da categoria
        if (t.category.displayName.toLowerCase().contains(searchQuery)) {
          return true;
        }
        return false;
      }).toList();
    }
    
    if (_showOnlyPeriodic) {
      filtered = filtered.where((t) => 
        t.frequency == TransactionFrequency.weekly || 
        t.frequency == TransactionFrequency.monthly
      ).toList();
    }
    
    if (_selectedPerson != null) {
      if (_selectedPerson == 'geral') {
        filtered = filtered.where((t) => t.person == null || t.person == 'geral' || t.person!.isEmpty).toList();
      } else {
        filtered = filtered.where((t) => t.person == _selectedPerson).toList();
      }
    }
    
    if (_selectedBudgetCategory != null) {
      filtered = filtered.where((t) {
        // Apenas despesas podem aparecer quando filtramos por categoria de orçamento
        // Ganhos não devem aparecer na lista de gastos
        if (t.type == TransactionType.despesa) {
          return t.expenseBudgetCategory == _selectedBudgetCategory;
        }
        return false;
      }).toList();
    }
    
    return filtered;
  }

  List<String> get _availablePersons {
    final persons = <String>{'geral'};
    for (var tx in widget.transactions) {
      if (tx.person != null && tx.person!.isNotEmpty) {
        persons.add(tx.person!);
      }
    }
    return persons.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transactions.isEmpty) {
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
    for (var transaction in _filteredTransactions) {
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

    // Obter o mês da primeira transação (mais recente)
    final displayMonth = sortedDates.isNotEmpty
        ? sortedDates.first
        : DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com mês das transações e filtros
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
              DateFormat('MMMM', Localizations.localeOf(context).toString())
                  .format(displayMonth),
              style: AppTheme.monospaceTextStyle(
                context: context,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.black,
              ),
                ),
                const SizedBox(height: 12),
                // Campo de busca
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Pesquisar por nome...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.lighterGray.withOpacity(0.2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    isDense: true,
                  ),
                  style: AppTheme.monospaceTextStyle(
                    context: context,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.black,
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                // Filtros
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Filtro de periódicas
                    FilterChip(
                      label: const Text('Periódicas', style: TextStyle(fontSize: 12)),
                      selected: _showOnlyPeriodic,
                      onSelected: (selected) {
                        setState(() {
                          _showOnlyPeriodic = selected;
                        });
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    // Filtro por pessoa - chips para cada pessoa
                    ..._availablePersons.map((person) => 
                      FilterChip(
                        label: Text(
                          person == 'geral' ? 'Todos' : person,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _selectedPerson == person,
                        onSelected: (selected) {
                          setState(() {
                            _selectedPerson = selected ? person : null;
                          });
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )
                    ),
                    // Filtros por categoria de orçamento
                    ...ExpenseBudgetCategory.values.map((category) => 
                      FilterChip(
                        label: Text(
                          category.displayName,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _selectedBudgetCategory == category,
                        onSelected: (selected) {
                        setState(() {
                            _selectedBudgetCategory = selected ? category : null;
                        });
                      },
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: sortedDates.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: AppTheme.lighterGray.withOpacity(0.3),
              ),
              itemBuilder: (context, index) {
                final date = sortedDates[index];
                final dateTransactions = groupedTransactions[date]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: dateTransactions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final transaction = entry.value;
                    return Column(
                      children: [
                        _TransactionCard(
                  transaction: transaction,
                  onTap: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TransactionDetailsScreen(
                          transaction: transaction,
                        ),
                        fullscreenDialog: true,
                      ),
                    );
                    if (result == true && widget.onTransactionUpdated != null) {
                      widget.onTransactionUpdated!();
                    }
                  },
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
                    if (result == true && widget.onTransactionUpdated != null) {
                      widget.onTransactionUpdated!();
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
                        if (widget.onTransactionUpdated != null) {
                          widget.onTransactionUpdated!();
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
                        ),
                        if (index < dateTransactions.length - 1)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: AppTheme.lighterGray.withOpacity(0.3),
                            indent: 0,
                            endIndent: 0,
                          ),
                      ],
                    );
                  }).toList(),
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
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _TransactionCard({
    required this.transaction,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  String _formatTimestamp(BuildContext context, DateTime date) {
    final dateFormat = DateFormat('d MMM, HH:mm', Localizations.localeOf(context).toString());
    return dateFormat.format(date);
  }

  String _getFrequencyLabel() {
    switch (transaction.frequency) {
      case TransactionFrequency.weekly:
        return 'Semanal';
      case TransactionFrequency.monthly:
        return 'Mensal';
      case TransactionFrequency.unique:
        return '';
    }
  }

  Color _getCategoryColor(ExpenseBudgetCategory? category) {
    if (category == null) return AppTheme.darkGray;
    switch (category) {
      case ExpenseBudgetCategory.gastos:
        return AppTheme.expensesRed;
      case ExpenseBudgetCategory.lazer:
        return AppTheme.leisureBlue;
      case ExpenseBudgetCategory.poupanca:
        return AppTheme.savingsYellow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho: data e ações
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
              children: [
                Icon(
                        Icons.circle,
                        size: 6,
                        color: AppTheme.lighterGray,
                ),
                      const SizedBox(width: 8),
                Text(
                  _formatTimestamp(context, transaction.date),
                  style: AppTheme.monospaceTextStyle(
                    context: context,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                    color: AppTheme.darkGray,
                  ),
                ),
              ],
            ),
                  ),
                // Ações
                Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    // Editar
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                            onTap: onEdit,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.lighterGray.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 16,
                            color: AppTheme.darkGray,
                          ),
                              ),
                            ),
                          ),
                    const SizedBox(width: 6),
                    // Excluir
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                            onTap: onDelete,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.lighterGray.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                              child: Icon(
                                Icons.delete_outline,
                                size: 16,
                            color: AppTheme.darkGray,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 12),
            // Descrição e valor
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: transaction.description != null && transaction.description!.isNotEmpty
                      ? Text(
                          transaction.description!,
                  style: AppTheme.monospaceTextStyle(
                    context: context,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                    color: AppTheme.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                        )
                      : transaction.category.displayName.isNotEmpty
                          ? Text(
                              transaction.category.displayName,
                              style: AppTheme.monospaceTextStyle(
                                context: context,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.black,
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
                const SizedBox(width: 12),
                // Valor destacado
                Text(
                  formatCurrency(transaction.amount),
                  style: AppTheme.monospaceTextStyle(
                    context: context,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.black,
                  ),
                ),
              ],
            ),
            // Tags
              if (transaction.person != null && transaction.person!.isNotEmpty ||
                  transaction.frequency != TransactionFrequency.unique ||
                  transaction.expenseBudgetCategory != null ||
                  (transaction.isSalary && transaction.salaryValues != null)) ...[
              const SizedBox(height: 12),
                Wrap(
                spacing: 6,
                runSpacing: 6,
                  children: [
                    if (transaction.person != null && transaction.person!.isNotEmpty)
                      Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                        color: AppTheme.lighterGray.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          transaction.person!,
                          style: AppTheme.monospaceTextStyle(
                            context: context,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                            color: AppTheme.darkGray,
                          ),
                        ),
                      ),
                    if (transaction.frequency != TransactionFrequency.unique)
                      Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                        color: AppTheme.lighterGray.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getFrequencyLabel(),
                          style: AppTheme.monospaceTextStyle(
                            context: context,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.darkGray,
                          ),
                        ),
                      ),
                    if (transaction.expenseBudgetCategory != null)
                      Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                        color: _getCategoryColor(transaction.expenseBudgetCategory).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _getCategoryColor(transaction.expenseBudgetCategory).withOpacity(0.3),
                          width: 1,
                        ),
                  ),
                        child: Text(
                          transaction.expenseBudgetCategory!.displayName,
                          style: AppTheme.monospaceTextStyle(
                            context: context,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _getCategoryColor(transaction.expenseBudgetCategory),
                          ),
                        ),
                      ),
                    if (transaction.isSalary && transaction.salaryValues != null)
                      Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                        color: AppTheme.lighterGray.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Salário',
                  style: AppTheme.monospaceTextStyle(
                    context: context,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.darkGray,
                          ),
                  ),
                ),
              ],
            ),
          ],
            ],
        ),
      ),
    );
  }
}
