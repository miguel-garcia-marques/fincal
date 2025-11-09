import 'package:flutter/material.dart';
import '../models/period_history.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';
import '../services/database.dart';

class PeriodHistoryDialog extends StatelessWidget {
  final List<PeriodHistory> periods;
  final Function(PeriodHistory) onPeriodSelected;
  final Function(String) onPeriodDeleted;

  const PeriodHistoryDialog({
    super.key,
    required this.periods,
    required this.onPeriodSelected,
    required this.onPeriodDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Histórico de Períodos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Lista de períodos
            Flexible(
              child: periods.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text(
                        'Nenhum período salvo',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.darkGray,
                            ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: periods.length,
                      itemBuilder: (context, index) {
                        final period = periods[index];
                        return _PeriodHistoryItem(
                          period: period,
                          onTap: () {
                            onPeriodSelected(period);
                            Navigator.of(context).pop();
                          },
                          onDelete: () {
                            onPeriodDeleted(period.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodHistoryItem extends StatefulWidget {
  final PeriodHistory period;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PeriodHistoryItem({
    required this.period,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_PeriodHistoryItem> createState() => _PeriodHistoryItemState();
}

class _PeriodHistoryItemState extends State<_PeriodHistoryItem> {
  int? _transactionCount;
  bool _isLoading = true;
  final DatabaseService _databaseService = DatabaseService();

  @override
  void initState() {
    super.initState();
    _loadTransactionCount();
  }

  Future<void> _loadTransactionCount() async {
    try {
      final transactions = await _databaseService.getTransactionsInRange(
        widget.period.startDate,
        widget.period.endDate,
      );
      if (mounted) {
        setState(() {
          _transactionCount = transactions.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Erro ao carregar contagem de transações: $e');
      if (mounted) {
        setState(() {
          _transactionCount = widget.period.transactionIds.length;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppTheme.darkGray.withOpacity(0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDate(widget.period.startDate)} - ${formatDate(widget.period.endDate)}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  _isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.darkGray,
                            ),
                          ),
                        )
                      : Text(
                          '${_transactionCount ?? widget.period.transactionIds.length} transações',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.darkGray,
                              ),
                        ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirmar exclusão'),
                    content: const Text(
                      'Tem certeza que deseja excluir este período?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onDelete();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.expenseRed,
                        ),
                        child: const Text('Excluir'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete_outline, color: AppTheme.expenseRed),
            ),
          ],
        ),
      ),
    );
  }
}

