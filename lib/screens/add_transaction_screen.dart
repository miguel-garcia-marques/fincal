import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/database.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

class AddTransactionScreen extends StatefulWidget {
  final Transaction? transactionToEdit;

  const AddTransactionScreen({super.key, this.transactionToEdit});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  int _currentStep = 0;
  late TransactionType _selectedType;
  late DateTime _selectedDate;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _personController = TextEditingController();
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
      _personController.text = t.person ?? '';
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
    _personController.dispose();
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
        _poupancaPercentController.text =
            (poupanca + remaining).toStringAsFixed(1);
      }
    }
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0: // Tipo e categoria
        return true;
      case 1: // Data e periodicidade
        if (_frequency == TransactionFrequency.weekly) {
          return _selectedDayOfWeek != null;
        } else if (_frequency == TransactionFrequency.monthly) {
          return _selectedDayOfMonth != null;
        }
        return true;
      case 2: // Valor e nome
        if (_formKey.currentState != null) {
          return _formKey.currentState!.validate();
        }
        return false;
      case 3: // Orçamento
        if (_selectedType == TransactionType.ganho && _isSalary) {
          final gastos = double.tryParse(_gastosPercentController.text) ?? 0;
          final lazer = double.tryParse(_lazerPercentController.text) ?? 0;
          final poupanca =
              double.tryParse(_poupancaPercentController.text) ?? 0;
          final total = gastos + lazer + poupanca;
          return (total - 100).abs() < 0.1;
        } else if (_selectedType == TransactionType.despesa) {
          return _expenseBudgetCategory != null;
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _saveTransaction() async {
    if (!_validateStep(3)) {
      setState(() {
        _currentStep = 3;
      });
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, insira um valor válido')),
      );
      return;
    }

    SalaryAllocation? salaryAllocation;
    if (_selectedType == TransactionType.ganho && _isSalary) {
      final gastos = double.tryParse(_gastosPercentController.text) ?? 0;
      final lazer = double.tryParse(_lazerPercentController.text) ?? 0;
      final poupanca = double.tryParse(_poupancaPercentController.text) ?? 0;

      salaryAllocation = SalaryAllocation(
        gastosPercent: gastos,
        lazerPercent: lazer,
        poupancaPercent: poupanca,
      );
    }

    int? dayOfWeek;
    int? dayOfMonth;
    if (_frequency == TransactionFrequency.weekly) {
      dayOfWeek = _selectedDayOfWeek;
    } else if (_frequency == TransactionFrequency.monthly) {
      dayOfMonth = _selectedDayOfMonth;
    }

    final transaction = Transaction(
      id: widget.transactionToEdit?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: _selectedType,
      date: _selectedDate,
      description: _nameController.text.isEmpty ? null : _nameController.text,
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
      person: _personController.text.isEmpty ? null : _personController.text,
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 600,
              maxHeight: 700,
            ),
            decoration: BoxDecoration(
              color: AppTheme.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.lighterGray.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header com título e botão fechar
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.lighterGray,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.transactionToEdit != null
                              ? 'Editar Transação'
                              : 'Nova Transação',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.black,
                                  ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.black),
                        onPressed: () => Navigator.of(context).pop(false),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // Progress indicator
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: List.generate(4, (index) {
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
                          height: 4,
                          decoration: BoxDecoration(
                            color: index <= _currentStep
                                ? AppTheme.black
                                : AppTheme.lighterGray.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // Step content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: _buildStepContent(),
                    ),
                  ),
                ),
                // Navigation buttons
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    border: Border(
                      top: BorderSide(
                        color: AppTheme.lighterGray.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _currentStep--;
                            });
                          },
                          child: const Text('Anterior'),
                        )
                      else
                        const SizedBox(),
                      ElevatedButton(
                        onPressed: () {
                          if (_currentStep < 3) {
                            if (_validateStep(_currentStep)) {
                              setState(() {
                                _currentStep++;
                              });
                            }
                          } else {
                            _saveTransaction();
                          }
                        },
                        child: Text(_currentStep < 3 ? 'Próximo' : 'Salvar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tipo de Transação',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 24),
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
                  if (!_getGainCategories().contains(_selectedCategory)) {
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
                  if (_getGainCategories().contains(_selectedCategory)) {
                    _selectedCategory = TransactionCategory.miscelaneos;
                  }
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Categoria',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TransactionCategory>(
          value: _getAvailableCategories().contains(_selectedCategory)
              ? _selectedCategory
              : _getAvailableCategories().first,
          decoration: const InputDecoration(),
          items: _getAvailableCategories().map((category) {
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
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Periodicidade',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 24),
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
        const SizedBox(height: 24),
        if (_frequency == TransactionFrequency.weekly) ...[
          Text(
            'Dia da Semana',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          // Botões para os 5 dias úteis (segunda a sexta) - apenas inicial
          Row(
            children: [
              Expanded(child: _buildDayButton(1)),
              const SizedBox(width: 6),
              Expanded(child: _buildDayButton(2)),
              const SizedBox(width: 6),
              Expanded(child: _buildDayButton(3)),
              const SizedBox(width: 6),
              Expanded(child: _buildDayButton(4)),
              const SizedBox(width: 6),
              Expanded(child: _buildDayButton(5)),
              const SizedBox(width: 6),
              Expanded(child: _buildDayButton(6)),
              const SizedBox(width: 6),
              Expanded(child: _buildDayButton(7)),
            ],
          ),
        ] else if (_frequency == TransactionFrequency.monthly) ...[
          Text(
            'Dia do Mês',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          // Grid simples de dias 1-31
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildMonthDayPicker(),
          ),
        ] else ...[
          Text(
            'Data',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _selectDate(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.lighterGray),
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
        ],
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Valor',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
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
        const SizedBox(height: 32),
        Text(
          'Nome',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
        const SizedBox(height: 32),
        Text(
          'Pessoa (opcional)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _personController,
          decoration: const InputDecoration(
            hintText: 'Deixe vazio para "geral"',
          ),
        ),
      ],
    );
  }

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedType == TransactionType.ganho) ...[
          Text(
            'Configuração de Salário',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 24),
          CheckboxListTile(
            title: const Text('É salário?'),
            value: _isSalary,
            onChanged: (value) {
              setState(() {
                _isSalary = value ?? false;
                if (_isSalary) {
                  _gastosPercentController.text = '50.0';
                  _lazerPercentController.text = '30.0';
                  _poupancaPercentController.text = '20.0';
                } else {
                  _gastosPercentController.clear();
                  _lazerPercentController.clear();
                  _poupancaPercentController.clear();
                }
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_isSalary) ...[
            const SizedBox(height: 24),
            Text(
              'Distribuição do Salário (%)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _gastosPercentController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Poupança %',
                      hintText: '20',
                    ),
                    onChanged: (_) => _validatePercentages(),
                  ),
                ),
              ],
            ),
          ],
        ] else ...[
          Text(
            'Categoria de Orçamento',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 24),
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
        ],
      ],
    );
  }

  Widget _buildDayButton(int dayOfWeek) {
    final isSelected = _selectedDayOfWeek == dayOfWeek;
    // Obter nome do dia no idioma do dispositivo e pegar apenas a inicial
    // dayOfWeek no sistema: 0=sábado, 1=domingo, 2=segunda, 3=terça, 4=quarta, 5=quinta, 6=sexta
    // DateTime.weekday: 1=segunda, 2=terça, 3=quarta, 4=quinta, 5=sexta, 6=sábado, 7=domingo
    // Mapear: dayOfWeek 2->weekday 1, 3->2, 4->3, 5->4, 6->5
    final dateFormat =
        DateFormat('EEEE', Localizations.localeOf(context).toString());
    // 2024-01-01 é segunda-feira (weekday=1, dayOfWeek=2)
    // Para dayOfWeek=2 (segunda): 2024-01-01 (weekday=1)
    // Para dayOfWeek=3 (terça): 2024-01-02 (weekday=2)
    // Para dayOfWeek=4 (quarta): 2024-01-03 (weekday=3)
    // Para dayOfWeek=5 (quinta): 2024-01-04 (weekday=4)
    // Para dayOfWeek=6 (sexta): 2024-01-05 (weekday=5)
    final referenceDate = DateTime(2024, 1, dayOfWeek - 1);
    final dayName = dateFormat.format(referenceDate);
    final initial = dayName.isNotEmpty ? dayName[0].toUpperCase() : '';

    return InkWell(
      onTap: () => setState(() => _selectedDayOfWeek = dayOfWeek),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.black
              : AppTheme.lighterGray.withOpacity(0.3),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            initial,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppTheme.white : AppTheme.black,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthDayPicker() {
    // Mostrar apenas os dias 1-31 em grid
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: 31,
      itemBuilder: (context, index) {
        final dayNumber = index + 1;
        final isSelected = _selectedDayOfMonth == dayNumber;

        return InkWell(
          onTap: () => setState(() => _selectedDayOfMonth = dayNumber),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.black : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? AppTheme.black
                    : AppTheme.lighterGray.withOpacity(0.3),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '$dayNumber',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? AppTheme.white : AppTheme.black,
                    ),
              ),
            ),
          ),
        );
      },
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? (type == TransactionType.ganho
                  ? AppTheme.incomeGreen
                  : AppTheme.expenseRed)
              : AppTheme.lighterGray.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.white,
                ),
          ),
        ),
      ),
    );
  }
}
