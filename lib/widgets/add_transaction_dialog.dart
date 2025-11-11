import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/transaction.dart';
import '../services/database.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

class AddTransactionDialog extends StatefulWidget {
  final Transaction? transactionToEdit;

  const AddTransactionDialog({super.key, this.transactionToEdit});

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  late TransactionType _selectedType;
  late DateTime _selectedDate;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  late TransactionCategory _selectedCategory;
  final _formKey = GlobalKey<FormState>();

  // Novos campos
  bool _isSalary = false;
  final TextEditingController _gastosPercentController =
      TextEditingController();
  final TextEditingController _lazerPercentController = TextEditingController();
  final TextEditingController _poupancaPercentController =
      TextEditingController();
  ExpenseBudgetCategory? _expenseBudgetCategory;
  TransactionFrequency _frequency = TransactionFrequency.unique;
  int? _selectedDayOfWeek;
  int? _selectedDayOfMonth;

  @override
  void initState() {
    super.initState();
    if (widget.transactionToEdit != null) {
      final t = widget.transactionToEdit!;
      _selectedType = t.type;
      _selectedDate = t.date;
      _nameController.text = t.description ?? '';
      _descriptionController.text = '';
      _amountController.text = t.amount.toStringAsFixed(2);
      _selectedCategory = t.category;
      _isSalary = t.isSalary;
      _expenseBudgetCategory = t.expenseBudgetCategory;
      _frequency = t.frequency;
      _selectedDayOfWeek = t.dayOfWeek;
      _selectedDayOfMonth = t.dayOfMonth;

      if (t.salaryAllocation != null) {
        _gastosPercentController.text =
            t.salaryAllocation!.gastosPercent.toStringAsFixed(1);
        _lazerPercentController.text =
            t.salaryAllocation!.lazerPercent.toStringAsFixed(1);
        _poupancaPercentController.text =
            t.salaryAllocation!.poupancaPercent.toStringAsFixed(1);
      }
    } else {
      _selectedType = TransactionType.despesa;
      _selectedDate = DateTime.now();
      _selectedCategory = TransactionCategory.miscelaneos;
    }

    // Se for ganho e não tiver categoria válida, definir padrão
    if (_selectedType == TransactionType.ganho &&
        !_getGainCategories().contains(_selectedCategory)) {
      _selectedCategory = TransactionCategory.salario;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _gastosPercentController.dispose();
    _lazerPercentController.dispose();
    _poupancaPercentController.dispose();
    super.dispose();
  }

  List<TransactionCategory> _getGainCategories() {
    return [
      TransactionCategory.salario,
      TransactionCategory.alimentacao,
      TransactionCategory.outro,
    ];
  }

  List<TransactionCategory> _getAvailableCategories() {
    if (_selectedType == TransactionType.ganho) {
      return _getGainCategories();
    } else {
      // Retornar todas as categorias exceto as de ganhos
      return TransactionCategory.values
          .where((cat) => !_getGainCategories().contains(cat))
          .toList();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppTheme.incomeGreen,
                  onPrimary: AppTheme.white,
                  surface: AppTheme.white,
                  onSurface: AppTheme.black,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      // Garantir que a data é apenas data, sem hora/timezone
      final dateOnly = DateTime(picked.year, picked.month, picked.day);
      if (dateOnly.year != _selectedDate.year ||
          dateOnly.month != _selectedDate.month ||
          dateOnly.day != _selectedDate.day) {
        setState(() {
          _selectedDate = dateOnly;
        });
      }
    }
  }

  void _validatePercentages() {
    final gastos = double.tryParse(_gastosPercentController.text) ?? 0;
    final lazer = double.tryParse(_lazerPercentController.text) ?? 0;
    final poupanca = double.tryParse(_poupancaPercentController.text) ?? 0;
    final total = gastos + lazer + poupanca;

    if (total != 100) {
      final remaining = 100 - total;
      if (remaining > 0) {
        // Ajustar automaticamente o campo de poupança
        _poupancaPercentController.text =
            (poupanca + remaining).toStringAsFixed(1);
      }
    }
  }

  Future<void> _saveTransaction() async {
    if (_formKey.currentState!.validate()) {
      final amount =
          double.tryParse(_amountController.text.replaceAll(',', '.'));
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, insira um valor válido')),
        );
        return;
      }

      // Validar percentagens se for salário
      SalaryAllocation? salaryAllocation;
      if (_selectedType == TransactionType.ganho && _isSalary) {
        final gastos = double.tryParse(_gastosPercentController.text) ?? 0;
        final lazer = double.tryParse(_lazerPercentController.text) ?? 0;
        final poupanca = double.tryParse(_poupancaPercentController.text) ?? 0;
        final total = gastos + lazer + poupanca;

        if ((total - 100).abs() > 0.1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('As percentagens devem somar 100%')),
          );
          return;
        }

        salaryAllocation = SalaryAllocation(
          gastosPercent: gastos,
          lazerPercent: lazer,
          poupancaPercent: poupanca,
        );
      }

      // Validar categoria de despesa
      if (_selectedType == TransactionType.despesa &&
          _expenseBudgetCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Por favor, selecione uma categoria de orçamento')),
        );
        return;
      }

      // Validar periodicidade
      int? dayOfWeek;
      int? dayOfMonth;
      if (_frequency == TransactionFrequency.weekly) {
        if (_selectedDayOfWeek == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Por favor, selecione um dia da semana')),
          );
          return;
        }
        dayOfWeek = _selectedDayOfWeek;
      } else if (_frequency == TransactionFrequency.monthly) {
        if (_selectedDayOfMonth == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Por favor, selecione um dia do mês')),
          );
          return;
        }
        dayOfMonth = _selectedDayOfMonth;
      }

      final transaction = Transaction(
        id: widget.transactionToEdit?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        type: _selectedType,
        date: _selectedDate,
        description: _nameController.text.isEmpty
            ? null
            : _nameController.text,
        amount: amount,
        category: _selectedCategory,
        isSalary: _isSalary,
        salaryAllocation: salaryAllocation,
        expenseBudgetCategory: _selectedType == TransactionType.despesa
            ? _expenseBudgetCategory
            : null,
        frequency: _frequency,
        dayOfWeek: dayOfWeek,
        dayOfMonth: dayOfMonth,
      );

      try {
        final dbService = DatabaseService();
        if (widget.transactionToEdit != null) {
          await dbService.updateTransaction(transaction);
        } else {
          await dbService.saveTransaction(transaction);
        }
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.transactionToEdit != null
                      ? 'Editar Transação'
                      : 'Nova Transação',
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Tipo de transação
                Text(
                  'Tipo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TypeButton(
                        label: 'Ganho',
                        type: TransactionType.ganho,
                        isSelected: _selectedType == TransactionType.ganho,
                        onTap: () => setState(() {
                          _selectedType = TransactionType.ganho;
                          _expenseBudgetCategory = null;
                          // Se a categoria atual não for válida para ganhos, mudar para salário
                          if (!_getGainCategories()
                              .contains(_selectedCategory)) {
                            _selectedCategory = TransactionCategory.salario;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeButton(
                        label: 'Despesa',
                        type: TransactionType.despesa,
                        isSelected: _selectedType == TransactionType.despesa,
                        onTap: () => setState(() {
                          _selectedType = TransactionType.despesa;
                          _isSalary = false;
                          // Se a categoria atual for de ganhos, mudar para miscelâneos
                          if (_getGainCategories()
                              .contains(_selectedCategory)) {
                            _selectedCategory = TransactionCategory.miscelaneos;
                          }
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Checkbox Salário (apenas para ganhos)
                if (_selectedType == TransactionType.ganho) ...[
                  CheckboxListTile(
                    title: const Text('É salário?'),
                    value: _isSalary,
                    onChanged: (value) {
                      setState(() {
                        _isSalary = value ?? false;
                        // Definir valores padrão quando marcar como salário
                        if (_isSalary) {
                          _gastosPercentController.text = '50.0';
                          _lazerPercentController.text = '30.0';
                          _poupancaPercentController.text = '20.0';
                        } else {
                          // Limpar campos quando desmarcar
                          _gastosPercentController.clear();
                          _lazerPercentController.clear();
                          _poupancaPercentController.clear();
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 16),

                  // Percentagens (apenas se for salário)
                  if (_isSalary) ...[
                    Text(
                      'Distribuição do Salário (%)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _gastosPercentController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Gastos %',
                              hintText: '50',
                            ),
                            onChanged: (_) => _validatePercentages(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lazerPercentController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Lazer %',
                              hintText: '30',
                            ),
                            onChanged: (_) => _validatePercentages(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _poupancaPercentController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Poupança %',
                              hintText: '20',
                            ),
                            onChanged: (_) => _validatePercentages(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ],

                // Categoria de orçamento (apenas para despesas)
                if (_selectedType == TransactionType.despesa) ...[
                  Text(
                    'Categoria de Orçamento',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ExpenseBudgetCategory>(
                    value: _expenseBudgetCategory,
                    decoration: const InputDecoration(
                      hintText: 'Selecione uma categoria',
                    ),
                    items: ExpenseBudgetCategory.values.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _expenseBudgetCategory = value);
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Por favor, selecione uma categoria';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // Periodicidade
                Text(
                  'Periodicidade',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TransactionFrequency>(
                  value: _frequency,
                  decoration: const InputDecoration(),
                  items: TransactionFrequency.values.map((frequency) {
                    return DropdownMenuItem(
                      value: frequency,
                      child: Text(frequency.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _frequency = value ?? TransactionFrequency.unique;
                      _selectedDayOfWeek = null;
                      _selectedDayOfMonth = null;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Dia da semana (se semanal)
                if (_frequency == TransactionFrequency.weekly) ...[
                  Text(
                    'Dia da Semana',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedDayOfWeek,
                    decoration: const InputDecoration(
                      hintText: 'Selecione um dia',
                    ),
                    items: [
                      {'value': 1, 'label': 'Domingo'},
                      {'value': 2, 'label': 'Segunda-feira'},
                      {'value': 3, 'label': 'Terça-feira'},
                      {'value': 4, 'label': 'Quarta-feira'},
                      {'value': 5, 'label': 'Quinta-feira'},
                      {'value': 6, 'label': 'Sexta-feira'},
                      {'value': 0, 'label': 'Sábado'},
                    ].map((item) {
                      return DropdownMenuItem(
                        value: item['value'] as int,
                        child: Text(item['label'] as String),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => _selectedDayOfWeek = value),
                  ),
                  const SizedBox(height: 16),
                ],

                // Dia do mês (se mensal)
                if (_frequency == TransactionFrequency.monthly) ...[
                  Text(
                    'Dia do Mês',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedDayOfMonth,
                    decoration: const InputDecoration(
                      hintText: 'Selecione um dia',
                    ),
                    items: List.generate(31, (index) => index + 1).map((day) {
                      return DropdownMenuItem(
                        value: day,
                        child: Text('Dia $day'),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => _selectedDayOfMonth = value),
                  ),
                  const SizedBox(height: 16),
                ],

                // Data (apenas para transações únicas)
                if (_frequency == TransactionFrequency.unique) ...[
                  Text(
                    'Data',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDate(_selectedDate),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const Icon(Icons.calendar_today, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Valor
                Text(
                  'Valor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    prefixText: '€ ',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira um valor';
                    }
                    final amount = double.tryParse(value.replaceAll(',', '.'));
                    if (amount == null || amount <= 0) {
                      return 'Por favor, insira um valor válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Nome
                Text(
                  'Nome',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Nome da transação',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, insira um nome';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Tipologia
                Text(
                  'Tipologia',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final availableCategories = _getAvailableCategories();
                    // Garantir que a categoria selecionada está na lista disponível
                    if (!availableCategories.contains(_selectedCategory)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedCategory = availableCategories.first;
                          });
                        }
                      });
                    }

                    return DropdownButtonFormField<TransactionCategory>(
                      value: availableCategories.contains(_selectedCategory)
                          ? _selectedCategory
                          : availableCategories.first,
                      decoration: const InputDecoration(),
                      items: availableCategories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category.displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedCategory = value);
                        }
                      },
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Botões
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveTransaction,
                        child: Text(widget.transactionToEdit != null
                            ? 'Atualizar'
                            : 'Adicionar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final TransactionType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (type == TransactionType.ganho
                  ? AppTheme.incomeGreen
                  : AppTheme.expenseRed)
              : AppTheme.lighterGray.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (type == TransactionType.ganho
                    ? AppTheme.incomeGreen
                    : AppTheme.expenseRed)
                : AppTheme.lighterGray,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppTheme.white : AppTheme.black,
                ),
          ),
        ),
      ),
    );
  }
}
