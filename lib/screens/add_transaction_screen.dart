import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/transaction.dart';
import '../services/database.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../utils/zeller_formula.dart';

class AddTransactionScreen extends StatefulWidget {
  final Transaction? transactionToEdit;
  final String walletId;
  final String userId;
  final bool skipImportOption;
  final DateTime? initialDate;
  final double? initialAmount;
  final String? initialDescription;
  final TransactionCategory? initialCategory;
  final TransactionType? initialType;

  const AddTransactionScreen({
    super.key,
    this.transactionToEdit,
    required this.walletId,
    required this.userId,
    this.skipImportOption = false,
    this.initialDate,
    this.initialAmount,
    this.initialDescription,
    this.initialCategory,
    this.initialType,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  bool _showImportOption = true; // Mostrar opção de importar primeiro
  int _currentStep = 0;
  late TransactionType _selectedType;
  late DateTime _selectedDate;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _personController = TextEditingController();
  late TransactionCategory _selectedCategory;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  bool _isSaving = false;

  // Focus nodes para scroll automático
  final Map<String, GlobalKey> _fieldKeys = {};

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
  bool _isProcessingImage = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Inicializar keys para os campos
    _fieldKeys['amount'] = GlobalKey();
    _fieldKeys['name'] = GlobalKey();
    _fieldKeys['person'] = GlobalKey();
    _fieldKeys['gastos'] = GlobalKey();
    _fieldKeys['lazer'] = GlobalKey();
    _fieldKeys['poupanca'] = GlobalKey();
    
    // Se estiver editando ou se skipImportOption for true, não mostrar opção de importar
    if (widget.transactionToEdit != null || widget.skipImportOption) {
      _showImportOption = false;
    }
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
      // Converter do formato Zeller (0=sábado, 1=domingo, 2=segunda...) para formato do botão (1=domingo, 2=segunda...)
      if (t.dayOfWeek != null) {
        if (t.dayOfWeek == 0) {
          _selectedDayOfWeek = 7; // sábado
        } else {
          _selectedDayOfWeek = t.dayOfWeek; // domingo=1, segunda=2, etc.
        }
      }
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
      _selectedType = widget.initialType ?? TransactionType.despesa;
      _selectedDate = widget.initialDate ?? DateTime.now();
      _selectedCategory = widget.initialCategory ?? TransactionCategory.miscelaneos;

      // Preencher campos se vierem de extração de imagem
      if (widget.initialAmount != null) {
        _amountController.text = widget.initialAmount!.toStringAsFixed(2);
      }
      if (widget.initialDescription != null) {
        _nameController.text = widget.initialDescription!;
      }

      // Se houver data inicial, configurar recorrência automaticamente baseada na frequência
      if (widget.initialDate != null) {
        _configureRecurrenceFromDate(widget.initialDate!);
      }
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
    _scrollController.dispose();
    super.dispose();
  }

  void _configureRecurrenceFromDate(DateTime date) {
    // Configurar recorrência baseada na frequência selecionada
    // Esta função será chamada quando a frequência mudar também
    if (_frequency == TransactionFrequency.weekly) {
      // Usar o dia da semana do dia selecionado
      // getDayOfWeek retorna: 0=sábado, 1=domingo, 2=segunda, 3=terça, 4=quarta, 5=quinta, 6=sexta
      // O sistema de salvamento usa o mesmo formato Zeller (0=sábado, 1=domingo, 2=segunda...)
      // Mas o _buildDayButton usa: 1=domingo, 2=segunda, 3=terça, 4=quarta, 5=quinta, 6=sexta, 7=sábado
      // Precisamos converter para o formato usado pelo _buildDayButton
      final zellerDay = getDayOfWeek(date);
      // Converter de Zeller (0=sábado, 1=domingo, 2=segunda...) para formato do botão (1=domingo, 2=segunda...)
      // Zeller: 0=sáb, 1=dom, 2=seg, 3=ter, 4=qua, 5=qui, 6=sex
      // Botão: 1=dom, 2=seg, 3=ter, 4=qua, 5=qui, 6=sex, 7=sáb
      if (zellerDay == 0) {
        _selectedDayOfWeek = 7; // sábado
      } else {
        _selectedDayOfWeek = zellerDay; // domingo=1, segunda=2, etc.
      }
    } else if (_frequency == TransactionFrequency.monthly) {
      // Usar o dia do mês como recorrente
      _selectedDayOfMonth = date.day;
    }
    // Para unique, não precisa configurar nada, a data já está definida
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
                  primary: AppTheme.black,
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
    if (_isSaving) return; // Prevenir múltiplos cliques

    if (!_validateStep(3)) {
      setState(() {
        _currentStep = 3;
      });
      // Mostrar mensagem de erro visível
      String errorMessage = '';
      if (_selectedType == TransactionType.ganho && _isSalary) {
        final gastos = double.tryParse(_gastosPercentController.text) ?? 0;
        final lazer = double.tryParse(_lazerPercentController.text) ?? 0;
        final poupanca = double.tryParse(_poupancaPercentController.text) ?? 0;
        final total = gastos + lazer + poupanca;
        if ((total - 100).abs() >= 0.1) {
          errorMessage = 'As percentagens devem somar 100%';
        }
      } else if (_selectedType == TransactionType.despesa) {
        if (_expenseBudgetCategory == null) {
          errorMessage = 'Por favor, selecione uma categoria de orçamento';
        }
      }
      if (errorMessage.isNotEmpty && mounted) {
        _showErrorDialog(errorMessage);
      }
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      if (mounted) {
        _showErrorDialog('Por favor, insira um valor válido');
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

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
      // Converter do formato do botão (1=domingo, 2=segunda..., 7=sábado) para formato Zeller (0=sábado, 1=domingo, 2=segunda...)
      if (_selectedDayOfWeek != null) {
        if (_selectedDayOfWeek == 7) {
          dayOfWeek = 0; // sábado
        } else {
          dayOfWeek = _selectedDayOfWeek; // domingo=1, segunda=2, etc.
        }
      }
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
      walletId: widget.walletId,
      createdBy: widget.userId,
    );

    try {
      final dbService = DatabaseService();
      if (widget.transactionToEdit != null) {
        await dbService.updateTransaction(transaction,
            walletId: widget.walletId);
      } else {
        await dbService.saveTransaction(transaction, walletId: widget.walletId);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        _showErrorDialog('Erro ao salvar: $e');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _scrollToField(String fieldName) {
    final key = _fieldKeys[fieldName];
    if (key?.currentContext != null && _scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients && key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.1, // Alinhar um pouco acima do centro
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: _showImportOption
            ? screenHeight * 0.45
            : (screenHeight * 0.9 - keyboardHeight).clamp(400.0, screenHeight * 0.9),
      ),
      decoration: const BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.lighterGray,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Content
          _showImportOption
              ? _buildImportOptionScreen()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header com título e botão fechar
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.black,
                                  ),
                            ),
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.close, color: AppTheme.black),
                            onPressed: () => Navigator.of(context).pop(false),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    // Progress indicator - mais minimalista
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      child: Row(
                        children: List.generate(4, (index) {
                          return Expanded(
                            child: Container(
                              margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                              height: 3,
                              decoration: BoxDecoration(
                                color: index <= _currentStep
                                    ? (_currentStep < 3
                                        ? AppTheme.black
                                        : (_selectedType ==
                                                TransactionType.ganho
                                            ? AppTheme.incomeGreen
                                            : AppTheme.expenseRed))
                                    : AppTheme.lighterGray.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    // Step content - com altura flexível e padding otimizado
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              24, 
                              20, 
                              24, 
                              8 + MediaQuery.of(context).viewInsets.bottom + 100,
                            ),
                            child: Form(
                              key: _formKey,
                              child: _buildStepContent(),
                            ),
                          );
                        },
                      ),
                    ),
                    // Navigation buttons - melhorado e mais acessível
                    Container(
                      padding: EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 16,
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        border: Border(
                          top: BorderSide(
                            color: AppTheme.lighterGray.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_currentStep > 0)
                              TextButton(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          _currentStep--;
                                        });
                                      },
                                child: const Text('Anterior'),
                              )
                            else
                              const SizedBox(width: 80),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isSaving
                                    ? null
                                    : () {
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
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor: AppTheme.black,
                                  foregroundColor: AppTheme.white,
                                ),
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  AppTheme.white),
                                        ),
                                      )
                                    : Text(
                                        _currentStep < 3 ? 'Próximo' : 'Salvar',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildImportOptionScreen() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header minimalista
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  'Adicionar Transação',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.black,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.black, size: 20),
                onPressed: () => Navigator.of(context).pop(false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        // Opções - compacto e minimalista
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botão criar transação
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  onTap: () {
                    // Fechar a bottom sheet atual e abrir uma nova com o formulário
                    Navigator.of(context).pop();
                    // Usar um pequeno delay para garantir que a bottom sheet anterior foi fechada
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          isDismissible: true,
                          enableDrag: true,
                          builder: (context) => AddTransactionScreen(
                            walletId: widget.walletId,
                            userId: widget.userId,
                            transactionToEdit: widget.transactionToEdit,
                            skipImportOption: true,
                          ),
                        );
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.darkGray,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: AppTheme.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            color: AppTheme.darkGray,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Criar Nova Transação',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Botão tirar foto de fatura com IA
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  onTap: _processInvoiceImage,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.black,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.camera_alt,
                          color: AppTheme.black,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isProcessingImage
                                ? 'Processando imagem...'
                                : 'Tirar Foto da Fatura (IA)',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isProcessingImage)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Botão importar em bulk
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  onTap: _importBulkTransactions,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.black,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.upload_file,
                          color: AppTheme.black,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Importar Transações em Bulk',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 30),
      ],
    );
  }

  Future<void> _processInvoiceImage() async {
    if (_isProcessingImage) return;

    try {
      // Mostrar diálogo para escolher entre câmera e galeria
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Selecionar Imagem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tirar Foto'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Escolher da Galeria'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      // Solicitar permissão e capturar/selecionar imagem
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null) return;

      setState(() {
        _isProcessingImage = true;
      });

      // Converter imagem para base64
      final Uint8List imageBytes = await image.readAsBytes();
      final String base64Image = base64Encode(imageBytes);
      final String imageBase64 = 'data:image/jpeg;base64,$base64Image';

      // Processar imagem com IA
      final apiService = ApiService();
      final extractedData = await apiService.extractInvoiceFromImage(
        imageBase64,
        walletId: widget.walletId,
      );

      // Preparar dados para o formulário
      double? extractedAmount;
      String? extractedDescription;
      TransactionCategory? extractedCategory;
      DateTime? extractedDate;
      TransactionType extractedType = TransactionType.despesa;

      if (extractedData['amount'] != null) {
        extractedAmount = (extractedData['amount'] as num).toDouble();
      }

      if (extractedData['description'] != null) {
        extractedDescription = extractedData['description'] as String;
      }

      if (extractedData['category'] != null) {
        try {
          extractedCategory = TransactionCategory.values.firstWhere(
            (cat) => cat.name == extractedData['category'],
            orElse: () => TransactionCategory.miscelaneos,
          );
        } catch (e) {
          extractedCategory = TransactionCategory.miscelaneos;
        }
      }

      // Se houver data extraída, usar ela
      if (extractedData['date'] != null) {
        try {
          final dateStr = extractedData['date'] as String;
          final dateParts = dateStr.split('-');
          if (dateParts.length == 3) {
            extractedDate = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
            );
          }
        } catch (e) {
          // Se não conseguir parsear a data, usar data atual
        }
      }

      // Fechar a tela de importação
      Navigator.of(context).pop();

      // Abrir o formulário preenchido com os dados extraídos
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            isDismissible: true,
            enableDrag: true,
            builder: (context) => AddTransactionScreen(
              walletId: widget.walletId,
              userId: widget.userId,
              skipImportOption: true,
              initialDate: extractedDate,
              initialAmount: extractedAmount,
              initialDescription: extractedDescription,
              initialCategory: extractedCategory,
              initialType: extractedType,
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Erro ao processar imagem: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
        });
      }
    }
  }

  Future<void> _importBulkTransactions() async {
    // Fechar a bottom sheet atual e abrir uma nova para importação
    Navigator.of(context).pop();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ImportBulkTransactionsSheet(
        walletId: widget.walletId,
        onImportComplete: () {
          Navigator.of(context).pop(true);
        },
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
                fontSize: 20,
              ),
        ),
        const SizedBox(height: 20),
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
        const SizedBox(height: 28),
        Text(
          'Categoria',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<TransactionCategory>(
          value: _getAvailableCategories().contains(_selectedCategory)
              ? _selectedCategory
              : _getAvailableCategories().first,
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _selectedType == TransactionType.ganho
                    ? AppTheme.incomeGreen
                    : AppTheme.expenseRed,
                width: 2,
              ),
            ),
          ),
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
              // Se houver data selecionada, configurar recorrência automaticamente
              _configureRecurrenceFromDate(_selectedDate);
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
                fontSize: 20,
              ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: _fieldKeys['amount'],
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 18),
          onTap: () => _scrollToField('amount'),
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              // Converter vírgula para ponto enquanto digita
              String text = newValue.text.replaceAll(',', '.');

              // Garantir que só há um ponto decimal
              final parts = text.split('.');
              if (parts.length > 2) {
                return oldValue;
              }

              // Validar formato: apenas números e um ponto decimal
              if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text) &&
                  text.isNotEmpty) {
                return oldValue;
              }

              // Preservar a posição do cursor
              int cursorPosition = newValue.selection.baseOffset;
              // Ajustar posição se necessário após substituição
              if (newValue.text.contains(',') && !text.contains(',')) {
                // Vírgula foi substituída, manter posição
                cursorPosition = text.length;
              }

              return TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(
                  offset: cursorPosition > text.length
                      ? text.length
                      : cursorPosition,
                ),
              );
            }),
          ],
          decoration: InputDecoration(
            hintText: '0.00',
            prefixText: '€ ',
            prefixStyle:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _selectedType == TransactionType.ganho
                    ? AppTheme.incomeGreen
                    : AppTheme.expenseRed,
                width: 2,
              ),
            ),
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
        const SizedBox(height: 28),
        Text(
          'Nome',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: _fieldKeys['name'],
          controller: _nameController,
          onTap: () => _scrollToField('name'),
          decoration: InputDecoration(
            hintText: 'Nome da transação',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _selectedType == TransactionType.ganho
                    ? AppTheme.incomeGreen
                    : AppTheme.expenseRed,
                width: 2,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Por favor, insira um nome';
            }
            return null;
          },
        ),
        const SizedBox(height: 28),
        Text(
          'Pessoa (opcional)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: _fieldKeys['person'],
          controller: _personController,
          onTap: () => _scrollToField('person'),
          decoration: InputDecoration(
            hintText: 'Deixe vazio para "geral"',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lighterGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _selectedType == TransactionType.ganho
                    ? AppTheme.incomeGreen
                    : AppTheme.expenseRed,
                width: 2,
              ),
            ),
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

class _ImportBulkTransactionsSheet extends StatefulWidget {
  final String walletId;
  final VoidCallback onImportComplete;

  const _ImportBulkTransactionsSheet({
    required this.walletId,
    required this.onImportComplete,
  });

  @override
  State<_ImportBulkTransactionsSheet> createState() =>
      _ImportBulkTransactionsSheetState();
}

class _ImportBulkTransactionsSheetState
    extends State<_ImportBulkTransactionsSheet> {
  bool _isLoading = false;
  bool _isImporting = false;
  String? _errorMessage;
  String? _successMessage;
  int? _totalTransactions;
  int? _duplicateCount;
  int? _errorCount;
  List<Map<String, dynamic>>? _transactionsToImport;

  // Verificar se uma transação do JSON é duplicada de uma transação existente
  bool _isDuplicate(Map<String, dynamic> jsonTx, Transaction existingTx) {
    // Comparar periodicidade
    String? jsonFrequency;
    int? jsonDayOfWeek;
    int? jsonDayOfMonth;

    if (jsonTx['periodicity'] == 'mensal') {
      jsonFrequency = 'monthly';
      jsonDayOfMonth = int.tryParse(jsonTx['day']?.toString() ?? '');
    } else if (jsonTx['periodicity'] == 'semanal') {
      jsonFrequency = 'weekly';
      final dayStr = (jsonTx['dayofWeek'] ?? jsonTx['day'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final dayMap = {
        'domingo': 1,
        'dom': 1,
        'segunda': 2,
        'seg': 2,
        'terça': 2,
        'terca': 2,
        'ter': 2,
        'quarta': 4,
        'qua': 4,
        'quinta': 5,
        'qui': 5,
        'sexta': 6,
        'sex': 6,
        'sábado': 0,
        'sabado': 0,
        'sab': 0,
      };
      jsonDayOfWeek = dayMap[dayStr];
    } else {
      jsonFrequency = 'unique';
    }

    // Comparar frequência
    if (existingTx.frequency.name != jsonFrequency) return false;
    if (existingTx.frequency == TransactionFrequency.weekly &&
        existingTx.dayOfWeek != jsonDayOfWeek) return false;
    if (existingTx.frequency == TransactionFrequency.monthly &&
        existingTx.dayOfMonth != jsonDayOfMonth) return false;

    // Para transações únicas, comparar data
    if (jsonFrequency == 'unique') {
      DateTime? jsonDate;
      if (jsonTx['date'] != null) {
        jsonDate = DateTime.tryParse(jsonTx['date'].toString());
      }
      if (jsonDate != null) {
        final jsonDateOnly =
            DateTime(jsonDate.year, jsonDate.month, jsonDate.day);
        final existingDateOnly = DateTime(
            existingTx.date.year, existingTx.date.month, existingTx.date.day);
        if (jsonDateOnly != existingDateOnly) return false;
      }
    }

    // Comparar tipo
    final jsonType = jsonTx['type']?.toString();
    if (existingTx.type.name != jsonType) return false;

    // Comparar valor
    final jsonAmount = (jsonTx['value'] ?? jsonTx['amount'] ?? 0).toString();
    final jsonAmountNum = double.tryParse(jsonAmount.replaceAll(',', '.')) ?? 0;
    if ((existingTx.amount - jsonAmountNum).abs() > 0.01) return false;

    // Comparar categoria
    final jsonCategory = jsonTx['category']?.toString();
    if (existingTx.category.name != jsonCategory) return false;

    // Comparar descrição (se ambas tiverem)
    final jsonDesc = jsonTx['description']?.toString() ?? '';
    final existingDesc = existingTx.description ?? '';
    if (jsonDesc.isNotEmpty &&
        existingDesc.isNotEmpty &&
        jsonDesc != existingDesc) return false;

    // Comparar pessoa
    final jsonPerson = jsonTx['person']?.toString();
    final existingPerson = existingTx.person;
    if (jsonPerson != null && jsonPerson.isNotEmpty) {
      if (existingPerson != jsonPerson) return false;
    } else if (existingPerson != null && existingPerson.isNotEmpty) {
      return false;
    }

    return true;
  }

  Future<void> _selectFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _totalTransactions = null;
      _duplicateCount = null;
      _errorCount = null;
      _transactionsToImport = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.size > 0) {
        String fileContent;

        // Na web, usar bytes; em outras plataformas, usar path
        if (result.files.single.bytes != null) {
          fileContent = utf8.decode(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          final filePath = result.files.single.path!;
          fileContent = await File(filePath).readAsString();
        } else {
          throw Exception('Não foi possível ler o arquivo');
        }

        final jsonData = json.decode(fileContent) as List<dynamic>;
        final transactions =
            jsonData.map((e) => e as Map<String, dynamic>).toList();

        // Verificar duplicatas e erros
        final dbService = DatabaseService();
        final existingTransactions =
            await dbService.getAllTransactions(walletId: widget.walletId);

        final duplicates = <Map<String, dynamic>>[];
        final duplicateIndices = <int>[];
        final errors = <Map<String, dynamic>>[];

        for (int i = 0; i < transactions.length; i++) {
          final tx = transactions[i];
          bool hasError = false;
          String? errorMsg;

          // Validar campos obrigatórios
          if (tx['type'] == null) {
            hasError = true;
            errorMsg = 'Tipo não especificado';
          }
          if (tx['value'] == null && tx['amount'] == null) {
            hasError = true;
            errorMsg = 'Valor não especificado';
          }
          if (tx['category'] == null) {
            hasError = true;
            errorMsg = 'Categoria não especificada';
          }

          if (hasError) {
            errors.add({
              'index': i,
              'transaction': tx,
              'error': errorMsg,
            });
            continue;
          }

          // Verificar duplicatas
          for (var existingTx in existingTransactions) {
            if (_isDuplicate(tx, existingTx)) {
              duplicates.add({
                'index': i,
                'transaction': tx,
                'existingId': existingTx.id,
              });
              duplicateIndices.add(i);
              break;
            }
          }
        }

        // Preparar transações para importar (sem duplicatas e sem erros)
        final transactionsToImport = <Map<String, dynamic>>[];
        final errorIndices = errors.map((e) => e['index'] as int).toSet();
        for (int i = 0; i < transactions.length; i++) {
          if (!duplicateIndices.contains(i) && !errorIndices.contains(i)) {
            transactionsToImport.add(transactions[i]);
          }
        }

        if (mounted) {
          setState(() {
            _isLoading = false;
            _totalTransactions = transactions.length;
            _duplicateCount = duplicates.length;
            _errorCount = errors.length;
            _transactionsToImport = transactionsToImport;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erro ao processar arquivo: $e';
        });
      }
    }
  }

  Future<void> _confirmImport() async {
    if (_transactionsToImport == null || _transactionsToImport!.isEmpty) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final apiService = ApiService();
      final importResult = await apiService.importBulkTransactions(
        _transactionsToImport!,
        walletId: widget.walletId,
      );

      if (mounted) {
        final imported = importResult['imported'] as int? ?? 0;
        final message = importResult['message'] as String?;

        setState(() {
          _isImporting = false;
          _successMessage =
              message ?? '$imported transação(ões) importada(s) com sucesso';
        });

        // Aguardar um pouco antes de fechar
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          widget.onImportComplete();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = 'Erro ao importar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.lighterGray,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    'Importar Transações',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.black,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.black),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Content
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildContent(),
            ),
          ),
          // Padding para safe area
          SizedBox(height: safeAreaBottom > 0 ? safeAreaBottom : 20),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processando arquivo...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: AppTheme.expenseRed,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: AppTheme.expenseRed),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_successMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: AppTheme.incomeGreen,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _successMessage!,
            style: TextStyle(color: AppTheme.incomeGreen),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Mostrar resumo se o arquivo foi processado
    if (_totalTransactions != null) {
      final newCount = _transactionsToImport?.length ?? 0;
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.info_outline,
              size: 48,
              color: AppTheme.black,
            ),
            const SizedBox(height: 16),
            Text(
              'Resumo do Arquivo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildSummaryCard(
              'Total de Transações',
              '$_totalTransactions',
              AppTheme.black,
            ),
            const SizedBox(height: 12),
            _buildSummaryCard(
              'Novas para Importar',
              '$newCount',
              AppTheme.incomeGreen,
            ),
            if (_duplicateCount != null && _duplicateCount! > 0) ...[
              const SizedBox(height: 12),
              _buildSummaryCard(
                'Duplicadas',
                '$_duplicateCount',
                AppTheme.darkGray,
              ),
            ],
            if (_errorCount != null && _errorCount! > 0) ...[
              const SizedBox(height: 12),
              _buildSummaryCard(
                'Com Erro',
                '$_errorCount',
                AppTheme.expenseRed,
              ),
            ],
            const SizedBox(height: 24),
            if (newCount > 0) ...[
              ElevatedButton(
                onPressed: _isImporting ? null : _confirmImport,
                child: _isImporting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Importando...'),
                        ],
                      )
                    : const Text('Confirmar Importação'),
              ),
            ] else ...[
              Text(
                'Nenhuma transação nova para importar',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.darkGray),
              ),
            ],
          ],
        ),
      );
    }

    // Estado inicial - selecionar arquivo
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.upload_file,
          size: 48,
          color: AppTheme.black,
        ),
        const SizedBox(height: 16),
        const Text(
          'Selecione um arquivo JSON para importar transações.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _selectFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('Selecionar Arquivo JSON'),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
