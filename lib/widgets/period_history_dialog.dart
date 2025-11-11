import 'package:flutter/material.dart';
import '../models/period_history.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';
import '../services/database.dart';
import '../services/api_service.dart';

class PeriodHistoryDialog extends StatelessWidget {
  final List<PeriodHistory> periods;
  final Function(PeriodHistory) onPeriodSelected;
  final Function(String) onPeriodDeleted;
  final Function(PeriodHistory) onPeriodUpdated;

  const PeriodHistoryDialog({
    super.key,
    required this.periods,
    required this.onPeriodSelected,
    required this.onPeriodDeleted,
    required this.onPeriodUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 700,
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
                          onUpdate: (updatedPeriod) {
                            onPeriodUpdated(updatedPeriod);
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
  final Function(PeriodHistory) onUpdate;

  const _PeriodHistoryItem({
    required this.period,
    required this.onTap,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<_PeriodHistoryItem> createState() => _PeriodHistoryItemState();
}

class _PeriodHistoryItemState extends State<_PeriodHistoryItem> {
  int? _transactionCount;
  bool _isLoading = true;
  bool _isUpdating = false;
  final DatabaseService _databaseService = DatabaseService();
  final ApiService _apiService = ApiService();
  late PeriodHistory _currentPeriod;

  @override
  void initState() {
    super.initState();
    _currentPeriod = widget.period;
    _loadTransactionCount();
  }

  @override
  void didUpdateWidget(_PeriodHistoryItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period.id != widget.period.id || 
        oldWidget.period.name != widget.period.name) {
      _currentPeriod = widget.period;
    }
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

  Future<void> _showEditNameDialog(BuildContext context) async {
    final TextEditingController nameController = TextEditingController(
      text: _currentPeriod.name,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Nome do Período'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nome do período',
            hintText: 'Ex: Janeiro 2024, Férias, etc.',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            Navigator.of(context).pop(value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(nameController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.black,
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result != null && result != _currentPeriod.name) {
      await _updatePeriodName(result);
    }
  }

  Future<void> _updatePeriodName(String newName) async {
    setState(() {
      _isUpdating = true;
    });

    try {
      final updatedPeriod = await _apiService.updatePeriodHistory(
        _currentPeriod.id,
        newName,
      );

      if (mounted) {
        setState(() {
          _currentPeriod = updatedPeriod;
          _isUpdating = false;
        });
        widget.onUpdate(updatedPeriod);
      }
    } catch (e) {
      print('Erro ao atualizar nome do período: $e');
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar nome: $e'),
            backgroundColor: AppTheme.expenseRed,
          ),
        );
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
                  if (_currentPeriod.name.isNotEmpty)
                    Text(
                      _currentPeriod.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.black,
                          ),
                    ),
                  if (_currentPeriod.name.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    '${formatDate(_currentPeriod.startDate)} - ${formatDate(_currentPeriod.endDate)}',
                    style: _currentPeriod.name.isNotEmpty
                        ? Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.darkGray,
                            )
                        : Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                          '${_transactionCount ?? _currentPeriod.transactionIds.length} transações',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.darkGray,
                              ),
                        ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _isUpdating ? null : () => _showEditNameDialog(context),
                  icon: _isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined, color: AppTheme.black),
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
          ],
        ),
      ),
    );
  }
}

