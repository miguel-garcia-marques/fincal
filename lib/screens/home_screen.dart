import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import '../models/transaction.dart';
import '../models/budget_balances.dart';
import '../models/period_history.dart';
import '../services/database.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../utils/date_utils.dart';
import '../utils/responsive_fonts.dart';
import '../widgets/calendar.dart';
import '../widgets/transaction_list.dart';
import '../widgets/loading_screen.dart';
import 'add_transaction_screen.dart';
import '../widgets/day_details_dialog.dart';
import '../widgets/period_selector_dialog.dart';
import '../widgets/period_history_dialog.dart';
import '../widgets/period_selection_dialog.dart';
import '../widgets/balance_chart.dart';
import '../theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final ApiService _apiService = ApiService();
  final CacheService _cacheService = CacheService();

  String? _userName;
  bool _isLoadingUser = true;

  int _selectedYear = DateTime.now().year;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  bool _showTransactions = false;
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  bool _isInitialLoading = true; // Novo estado para loading inicial
  List<PeriodHistory> _periodHistories = [];
  bool _periodSelected = false;
  final GlobalKey<CalendarWidgetState> _calendarKey =
      GlobalKey<CalendarWidgetState>();
  bool _isFabMenuExpanded = false;
  Future<double>? _initialBalanceFuture;
  double? _cachedInitialBalance; // Cache do saldo inicial
  String? _filterPerson;
  Timer? _cacheRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Assume current year but don't set dates yet
    _selectedYear = DateTime.now().year;
    // Prompt for period selection after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeApp();
      // Iniciar timer de refresh automático a cada 30 segundos
      _startCacheRefreshTimer();
    });
  }

  @override
  void dispose() {
    _cacheRefreshTimer?.cancel();
    super.dispose();
  }

  // Iniciar timer para atualizar cache a cada 30 segundos
  void _startCacheRefreshTimer() {
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshDataInBackground(),
    );
  }

  // Método de inicialização otimizado com cache
  Future<void> _initializeApp() async {
    // 1. Carregar dados do cache primeiro (rápido)
    await _loadFromCache();

    // 2. Carregar dados do servidor em paralelo
    await Future.wait([
      _loadUserData(),
      _loadPeriodHistories(),
    ]);

    // 3. Se não tiver período selecionado do cache, selecionar
    if (!_periodSelected) {
      await _selectDateRangeOnStartup();
    } else {
      // Se já tiver período do cache, carregar transações
      await _loadTransactions(savePeriod: false, useCache: true);
    }

    // 4. Marcar loading inicial como completo
    if (mounted) {
      setState(() {
        _isInitialLoading = false;
      });
    }

    // 5. Atualizar dados em background se necessário
    _refreshDataInBackground();
  }

  // Carregar dados do cache
  Future<void> _loadFromCache() async {
    try {
      // Carregar período atual do cache
      final cachedPeriod = await _cacheService.getCachedCurrentPeriod();
      if (cachedPeriod != null) {
        setState(() {
          _startDate = cachedPeriod['startDate'] as DateTime;
          _endDate = cachedPeriod['endDate'] as DateTime;
          _selectedYear = cachedPeriod['selectedYear'] as int;
          _periodSelected = true;
        });
      }

      // Carregar períodos do cache
      final cachedPeriods = await _cacheService.getCachedPeriodHistories();
      if (cachedPeriods != null && cachedPeriods.isNotEmpty) {
        setState(() {
          _periodHistories = cachedPeriods;
        });
      }

      // Carregar transações do cache se tiver período selecionado
      if (_periodSelected) {
        final cachedTransactions = await _cacheService.getCachedTransactions();
        if (cachedTransactions != null && cachedTransactions.isNotEmpty) {
          setState(() {
            _transactions = cachedTransactions;
            _isLoading = false;
          });
          // Inicializar o saldo inicial para o gráfico poder ser exibido
          _initialBalanceFuture = _calculateInitialBalance();
        }
      }
    } catch (e) {
      print('Erro ao carregar do cache: $e');
    }
  }

  // Atualizar dados em background
  Future<void> _refreshDataInBackground() async {
    try {
      // Verificar se o cache é válido
      final isCacheValid = await _cacheService.isCacheValid();

      if (!isCacheValid) {
        // Atualizar períodos
        final periods = await _apiService.getAllPeriodHistories();
        if (mounted) {
          setState(() {
            _periodHistories = periods;
          });
          await _cacheService.cachePeriodHistories(periods);
        }

        // Atualizar transações se tiver período selecionado
        if (_periodSelected) {
          final transactions = await _databaseService.getTransactionsInRange(
            _startDate,
            _endDate,
          );
          if (mounted) {
            setState(() {
              _transactions = transactions;
            });
            await _cacheService.cacheTransactions(transactions);
          }
        }
      }
    } catch (e) {
      print('Erro ao atualizar dados em background: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _userService.getCurrentUser();
      if (mounted) {
        setState(() {
          _userName = user?.name;
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      print('Erro ao carregar dados do usuário: $e');
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    }
  }

  Future<void> _loadPeriodHistories() async {
    try {
      final periods = await _apiService.getAllPeriodHistories();
      if (mounted) {
        setState(() {
          _periodHistories = periods;
        });
        // Salvar no cache
        await _cacheService.cachePeriodHistories(periods);
      }
    } catch (e) {
      print('Erro ao carregar histórico de períodos: $e');
    }
  }

  Future<void> _selectDateRangeOnStartup() async {
    // Set default to current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);

    // Show period selection dialog if user has past periods
    if (_periodHistories.isNotEmpty) {
      final result = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PeriodSelectionDialog(
          pastPeriods: _periodHistories,
          currentYear: _selectedYear,
        ),
      );

      if (result != null && mounted) {
        if (result['type'] == 'existing') {
          final period = result['period'] as PeriodHistory;
          setState(() {
            _startDate = period.startDate;
            _endDate = period.endDate;
            _selectedYear = period.startDate.year;
            _periodSelected = true;
          });
          await _loadTransactions(savePeriod: false, useCache: false);
        } else if (result['type'] == 'new') {
          setState(() {
            _selectedYear = result['year'];
            _startDate = result['startDate'];
            _endDate = result['endDate'];
            _periodSelected = true;
          });
          await _loadTransactions(
              savePeriod: true,
              periodName: result['name'] as String? ?? '',
              useCache: false);
        }
      }
    } else {
      // No past periods, show period selector
      await _selectPeriod();
    }
  }

  Future<void> _loadTransactions({
    bool savePeriod = false,
    String periodName = '',
    bool useCache = false,
  }) async {
    setState(() => _isLoading = true);

    List<Transaction> transactions = [];

    // Tentar carregar do cache primeiro se solicitado
    if (useCache) {
      final cachedTransactions = await _cacheService.getCachedTransactions();
      if (cachedTransactions != null && cachedTransactions.isNotEmpty) {
        transactions = cachedTransactions;
        setState(() {
          _transactions = transactions;
          _isLoading = false;
        });
        // Continuar em background para atualizar
        _refreshTransactionsInBackground();
        return;
      }
    }

    // Carregar do servidor
    transactions = await _databaseService.getTransactionsInRange(
      _startDate,
      _endDate,
    );

    // Save period history with transaction IDs only if requested
    if (savePeriod) {
      final transactionIds = transactions.map((t) => t.id).toList();
      try {
        final periodHistory = PeriodHistory(
          id: '', // Will be generated by backend
          startDate: _startDate,
          endDate: _endDate,
          transactionIds: transactionIds,
          name: periodName,
        );
        await _apiService.savePeriodHistory(periodHistory);
        await _loadPeriodHistories();
      } catch (e) {
        print('Erro ao salvar histórico de período: $e');
      }
    }

    // Salvar no cache
    await _cacheService.cacheTransactions(transactions);
    await _cacheService.cacheCurrentPeriod(
      startDate: _startDate,
      endDate: _endDate,
      selectedYear: _selectedYear,
    );

    // Recriar a Future do saldo inicial quando o período mudar
    // Invalidar cache do saldo inicial quando período muda
    _cachedInitialBalance = null;
    _initialBalanceFuture = _calculateInitialBalance();

    setState(() {
      _transactions = transactions;
      _isLoading = false;
    });
  }

  // Atualizar transações em background
  Future<void> _refreshTransactionsInBackground() async {
    try {
      final transactions = await _databaseService.getTransactionsInRange(
        _startDate,
        _endDate,
      );
      if (mounted) {
        setState(() {
          _transactions = transactions;
        });
        await _cacheService.cacheTransactions(transactions);
      }
    } catch (e) {
      print('Erro ao atualizar transações em background: $e');
    }
  }

  Future<void> _selectPeriod() async {
    final result = await showDialog(
      context: context,
      builder: (context) => PeriodSelectorDialog(
        selectedYear: _selectedYear,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedYear = result['year'];
        _startDate = result['startDate'];
        _endDate = result['endDate'];
        _periodSelected = true;
      });
      await _loadTransactions(
          savePeriod: true, periodName: result['name'] as String? ?? '');
    }
  }

  Future<void> _showPeriodHistory() async {
    await showDialog(
      context: context,
      builder: (context) => PeriodHistoryDialog(
        periods: _periodHistories,
        onPeriodSelected: (period) async {
          setState(() {
            _startDate = period.startDate;
            _endDate = period.endDate;
            _selectedYear = period.startDate.year;
          });
          await _loadTransactions(savePeriod: false, useCache: false);
        },
        onPeriodDeleted: (id) async {
          try {
            await _apiService.deletePeriodHistory(id);
            await _loadPeriodHistories();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Período excluído com sucesso')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erro ao excluir período: $e')),
              );
            }
          }
        },
        onPeriodUpdated: (updatedPeriod) async {
          try {
            await _loadPeriodHistories();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Nome do período atualizado com sucesso')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erro ao atualizar período: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _showAddTransactionDialog() async {
    final result = await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => const AddTransactionScreen(),
    );

    if (result == true) {
      await _loadTransactions(savePeriod: false, useCache: false);
    }
  }

  Future<void> _showImportDialog() async {
    await showDialog(
      context: context,
      builder: (context) => _ImportTransactionsDialog(
        onImportComplete: () async {
          await _loadTransactions(savePeriod: false, useCache: false);
        },
      ),
    );
  }

  List<String> get _availablePersons {
    final persons = <String>{'geral'};
    for (var tx in _transactions) {
      if (tx.person != null && tx.person!.isNotEmpty) {
        persons.add(tx.person!);
      }
    }
    return persons.toList()..sort();
  }

  Widget _buildPersonFilter() {
    if (_availablePersons.length <= 1) {
      return const SizedBox.shrink();
    }

    return DropdownButton<String>(
      value: _filterPerson,
      hint: const Text('Todas'),
      isDense: true,
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Todas'),
        ),
        ..._availablePersons.map((person) => DropdownMenuItem<String>(
              value: person,
              child: Text(person == 'geral' ? 'Geral' : person),
            )),
      ],
      onChanged: (value) {
        setState(() {
          _filterPerson = value;
        });
      },
    );
  }

  Future<void> _showTransactionsAsPopup() async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;

    if (isDesktop) {
      // Desktop: usar dialog
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabeçalho do diálogo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transações',
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
                // Lista de transações
                Expanded(
                  child: TransactionListWidget(
                    transactions: _transactions,
                    onTransactionUpdated: () async {
                      await _loadTransactions(
                          savePeriod: false, useCache: false);
                      if (mounted) {
                        Navigator.of(context).pop();
                        _showTransactionsAsPopup();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Mobile: usar fullscreen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: AppTheme.white,
            appBar: AppBar(
              backgroundColor: AppTheme.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                'Transações',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.black,
                    ),
              ),
              centerTitle: true,
            ),
            body: TransactionListWidget(
              transactions: _transactions,
              onTransactionUpdated: () async {
                await _loadTransactions(savePeriod: false, useCache: false);
                if (mounted) {
                  Navigator.of(context).pop();
                  _showTransactionsAsPopup();
                }
              },
            ),
          ),
          fullscreenDialog: true,
        ),
      );
    }
  }

  Future<void> _showBalancePopup() async {
    final summary = _calculateSummary();
    final balance = summary['gains']! - summary['expenses']!;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho do diálogo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Resumo Financeiro',
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
              // Conteúdo: Saldo, Ganhos e Despesas
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Card de Saldo
                      _SummaryCard(
                        title: 'Saldo',
                        value: formatCurrency(balance),
                        color: AppTheme.darkGray,
                        isFullWidth: true,
                        isTall: true,
                      ),
                      const SizedBox(height: 16),
                      // Ganhos e Despesas lado a lado
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              title: 'Ganhos',
                              value: formatCurrency(summary['gains']!),
                              color: AppTheme.incomeGreen,
                              count: _transactions
                                  .where((t) => t.type == TransactionType.ganho)
                                  .length,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              title: 'Despesas',
                              value: formatCurrency(summary['expenses']!),
                              color: AppTheme.expenseRed,
                              count: _transactions
                                  .where(
                                      (t) => t.type == TransactionType.despesa)
                                  .length,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDayDetails(DateTime date) async {
    // Calcular saldo disponível para este dia
    final allTransactions = await _databaseService.getTransactionsInRange(
      _startDate,
      date,
    );

    double balance = 0.0;
    double gastos = 0.0;
    double lazer = 0.0;
    double poupanca = 0.0;

    for (var transaction in allTransactions) {
      final transactionDate = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      final checkDate = DateTime(date.year, date.month, date.day);

      if (transactionDate.isBefore(checkDate) ||
          transactionDate.isAtSameMomentAs(checkDate)) {
        if (transaction.type == TransactionType.ganho) {
          if (transaction.isSalary && transaction.salaryValues != null) {
            // Para salários, adicionar o valor total mas subtrair a poupança (que é despesa)
            final poupancaAmount = transaction.salaryValues!.poupanca;
            balance += transaction.amount - poupancaAmount;

            // Calcular valores do salário
            final values = transaction.salaryValues;
            gastos += values!.gastos;
            lazer += values.lazer;
            // Poupança é considerada despesa, então subtrair em vez de adicionar
            poupanca -= values.poupanca;
          } else if (transaction.category == TransactionCategory.alimentacao) {
            // Ganhos de alimentação entram como valor positivo em "gastos"
            balance += transaction.amount;
            gastos += transaction.amount;
          } else {
            balance += transaction.amount;
          }
        } else {
          balance -= transaction.amount;

          // Deduzir da categoria correspondente
          switch (transaction.expenseBudgetCategory) {
            case ExpenseBudgetCategory.gastos:
              gastos -= transaction.amount;
              break;
            case ExpenseBudgetCategory.lazer:
              lazer -= transaction.amount;
              break;
            case ExpenseBudgetCategory.poupanca:
              poupanca -= transaction.amount;
              break;
            case null:
              break;
          }
        }
      }
    }

    final dayTransactions = _transactions.where((t) {
      final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
      return isSameDay(transactionDate, date);
    }).toList();

    final budgetBalances = (gastos != 0 || lazer != 0 || poupanca != 0)
        ? BudgetBalances(gastos: gastos, lazer: lazer, poupanca: poupanca)
        : null;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => DayDetailsDialog(
          date: date,
          transactions: dayTransactions,
          availableBalance: balance,
          budgetBalances: budgetBalances,
          allPeriodTransactions: _transactions,
          periodStartDate: _startDate,
          periodEndDate: _endDate,
        ),
      );
    }
  }

  Map<String, double> _calculateSummary() {
    double totalGains = 0.0;
    double totalExpenses = 0.0;

    for (var transaction in _transactions) {
      if (transaction.type == TransactionType.ganho) {
        if (transaction.isSalary && transaction.salaryValues != null) {
          // Para salários, adicionar o valor total mas considerar a poupança como despesa
          final poupancaAmount = transaction.salaryValues!.poupanca;
          totalGains += transaction.amount;
          totalExpenses += poupancaAmount;
        } else {
          totalGains += transaction.amount;
        }
      } else {
        totalExpenses += transaction.amount;
      }
    }

    return {
      'gains': totalGains,
      'expenses': totalExpenses,
    };
  }

  String _formatPeriodDates(DateTime startDate, DateTime endDate) {
    final startDay = startDate.day.toString().padLeft(2, '0');
    final startMonth = startDate.month.toString().padLeft(2, '0');
    final endDay = endDate.day.toString().padLeft(2, '0');
    final endMonth = endDate.month.toString().padLeft(2, '0');

    return '$startDay/$startMonth - $endDay/$endMonth';
  }

  Future<double> _calculateInitialBalance() async {
    // Se já temos o saldo em cache e as transações não mudaram, retornar cache
    if (_cachedInitialBalance != null && _transactions.isNotEmpty) {
      // Verificar se o período ainda é o mesmo
      final cachedPeriod = await _cacheService.getCachedCurrentPeriod();
      if (cachedPeriod != null &&
          cachedPeriod['startDate'] == _startDate &&
          cachedPeriod['endDate'] == _endDate) {
        return _cachedInitialBalance!;
      }
    }

    // Calcular saldo de todas as transações antes do período começar
    try {
      final beforePeriod = _startDate.subtract(const Duration(days: 1));

      // Tentar usar transações já carregadas se possível
      double balance = 0.0;

      // Se temos transações carregadas, podemos calcular parcialmente
      // Mas ainda precisamos das transações antes do período
      final allTransactions = await _databaseService.getTransactionsInRange(
        DateTime(1900, 1, 1), // Data muito antiga para pegar todas
        beforePeriod,
      );

      for (var transaction in allTransactions) {
        if (transaction.type == TransactionType.ganho) {
          if (transaction.isSalary && transaction.salaryValues != null) {
            // Para salários, adicionar o valor total mas subtrair a poupança (que é despesa)
            final poupancaAmount = transaction.salaryValues!.poupanca;
            balance += transaction.amount - poupancaAmount;
          } else {
            balance += transaction.amount;
          }
        } else {
          balance -= transaction.amount;
        }
      }

      // Cachear o resultado
      _cachedInitialBalance = balance;
      return balance;
    } catch (e) {
      print('Erro ao calcular saldo inicial: $e');
      return 0.0;
    }
  }

  Map<DateTime, double> _calculateDailyBalancesForChart() {
    final days = getDaysInRange(_startDate, _endDate);
    final Map<DateTime, double> dailyBalances = {};

    if (_transactions.isEmpty) {
      for (var day in days) {
        final dayOnly = DateTime(day.year, day.month, day.day);
        dailyBalances[dayOnly] = 0.0;
      }
      return dailyBalances;
    }

    // Ordenar transações por data
    final sortedTransactions = List<Transaction>.from(_transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    int transactionIndex = 0;

    for (var day in days) {
      final currentDay = DateTime.utc(day.year, day.month, day.day);
      double dayBalance = 0.0;

      // Processar todas as transações deste dia
      while (transactionIndex < sortedTransactions.length) {
        final transaction = sortedTransactions[transactionIndex];
        final transactionDate = DateTime.utc(
          transaction.date.year,
          transaction.date.month,
          transaction.date.day,
        );

        if (transactionDate.isAfter(currentDay)) {
          break;
        }

        if (transactionDate.year == currentDay.year &&
            transactionDate.month == currentDay.month &&
            transactionDate.day == currentDay.day) {
          if (transaction.type == TransactionType.ganho) {
            if (transaction.isSalary && transaction.salaryValues != null) {
              // Para salários, adicionar o valor total mas subtrair a poupança (que é despesa)
              final poupancaAmount = transaction.salaryValues!.poupanca;
              dayBalance += transaction.amount - poupancaAmount;
            } else {
              dayBalance += transaction.amount;
            }
          } else {
            dayBalance -= transaction.amount;
          }
          transactionIndex++;
        } else {
          break;
        }
      }

      final dayOnly = DateTime(day.year, day.month, day.day);
      dailyBalances[dayOnly] = dayBalance;
    }

    return dailyBalances;
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar tela de loading durante inicialização
    if (_isInitialLoading) {
      return const LoadingScreen(
        message: 'Carregando seus dados financeiros...',
      );
    }

    final summary = _calculateSummary();
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;

    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Cabeçalho
                Container(
                  padding: EdgeInsets.all(isDesktop ? 24 : 12),
                  margin: EdgeInsets.only(bottom: isDesktop ? 20 : 14),
                  decoration: const BoxDecoration(
                    color: AppTheme.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FinCal',
                        style:
                            Theme.of(context).textTheme.displayMedium?.copyWith(
                                  fontSize: isDesktop
                                      ? ResponsiveFonts.getFontSize(context, 32)
                                      : null,
                                ),
                      ),
                      Row(
                        children: [
                          // Filtro por pessoa
                          _buildPersonFilter(),
                          const SizedBox(width: 8),
                          // Botão do menu (sem o menu expandido aqui)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _isFabMenuExpanded = !_isFabMenuExpanded;
                              });
                            },
                            icon: Icon(
                              _isFabMenuExpanded ? Icons.close : Icons.menu,
                              color: AppTheme.black,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: _isFabMenuExpanded
                                  ? AppTheme.darkGray.withOpacity(0.1)
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Conteúdo principal
                Expanded(
                  child: !_periodSelected
                      ? const Center(child: CircularProgressIndicator())
                      : _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Stack(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 0, vertical: 0),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final layoutWidth = constraints.maxWidth;
                                      final usePopupForTransactions =
                                          layoutWidth < 1300;
                                      final isDesktopLayout =
                                          layoutWidth >= 1400;

                                      if (isDesktopLayout) {
                                        // Desktop layout: sempre calendário à esquerda e lista à direita
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Calendário
                                            Expanded(
                                              flex: 3,
                                              child: CalendarWidget(
                                                key: _calendarKey,
                                                startDate: _startDate,
                                                endDate: _endDate,
                                                transactions: _transactions,
                                                onDayTap: _showDayDetails,
                                                filterPerson: _filterPerson,
                                              ),
                                            ),
                                            // Lista de transações (sempre visível no desktop)
                                            const SizedBox(width: 24),
                                            Expanded(
                                              flex: 2,
                                              child: TransactionListWidget(
                                                transactions: _transactions,
                                                onTransactionUpdated: () async {
                                                  await _loadTransactions(
                                                      savePeriod: false,
                                                      useCache: false);
                                                },
                                              ),
                                            ),
                                          ],
                                        );
                                      }

                                      // Mobile/Tablet layout
                                      return ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 650),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Calendário e Gráfico
                                            Expanded(
                                              flex: _showTransactions &&
                                                      !usePopupForTransactions
                                                  ? 2
                                                  : 1,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  // Calendário
                                                  Expanded(
                                                    child: CalendarWidget(
                                                      key: _calendarKey,
                                                      startDate: _startDate,
                                                      endDate: _endDate,
                                                      transactions:
                                                          _transactions,
                                                      onDayTap: _showDayDetails,
                                                      filterPerson:
                                                          _filterPerson,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Lista de transações (só mostra ao lado se não for popup)
                                            if (_showTransactions &&
                                                !usePopupForTransactions) ...[
                                              const SizedBox(width: 12),
                                              Expanded(
                                                flex: 1,
                                                child: TransactionListWidget(
                                                  transactions: _transactions,
                                                  onTransactionUpdated:
                                                      () async {
                                                    await _loadTransactions(
                                                        savePeriod: false,
                                                        useCache: false);
                                                  },
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                ),

                // Gráfico de progressão
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final shouldHideChart = screenHeight < 700;

                    if (shouldHideChart) {
                      return const SizedBox.shrink();
                    }

                    return Container(
                      // padding: EdgeInsets.symmetric(
                      //   horizontal: isDesktop ? 24 : 12,
                      //   vertical: isDesktop ? 16 : 20,
                      // ),
                      padding: EdgeInsets.only(
                          bottom: 10,
                          top: isDesktop ? 16 : 20,
                          left: isDesktop ? 24 : 12,
                          right: isDesktop ? 24 : 12),
                      decoration: const BoxDecoration(
                        color: AppTheme.white,
                      ),
                      child: FutureBuilder<double>(
                        future: _initialBalanceFuture ?? Future.value(0.0),
                        builder: (context, snapshot) {
                          // Sempre mostrar o gráfico, mesmo durante loading
                          // Usar saldo em cache se disponível, senão usar 0.0
                          final initialBalance =
                              _cachedInitialBalance ?? snapshot.data ?? 0.0;

                          return BalanceChart(
                            startDate: _startDate,
                            endDate: _endDate,
                            dailyBalances: _calculateDailyBalancesForChart(),
                            initialBalance: initialBalance,
                          );
                        },
                      ),
                    );
                  },
                ),

                // Resumo mensal
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final shouldShowBalanceAsPopup = screenHeight < 700;

                    if (shouldShowBalanceAsPopup) {
                      // Layout em coluna para ecrãs pequenos: Período em cima, Resumo em baixo
                      return Container(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        decoration: const BoxDecoration(
                          color: AppTheme.white,
                        ),
                        child: Column(
                          children: [
                            // Período - em cima
                            InkWell(
                              onTap: _selectPeriod,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.darkGray.withOpacity(0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // "Período" e ano juntos na mesma linha
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            'Período',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppTheme.darkGray,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        if (_startDate.year == _endDate.year)
                                          Flexible(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.darkGray
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${_startDate.year}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      fontSize: ResponsiveFonts
                                                          .getFontSize(
                                                              context, 9),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppTheme.darkGray,
                                                    ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                        else
                                          Flexible(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.darkGray
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      '${_startDate.year}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            fontSize:
                                                                ResponsiveFonts
                                                                    .getFontSize(
                                                                        context,
                                                                        9),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppTheme
                                                                .darkGray,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 2),
                                                  child: Text(
                                                    '-',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontSize:
                                                              ResponsiveFonts
                                                                  .getFontSize(
                                                                      context,
                                                                      9),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              AppTheme.darkGray,
                                                        ),
                                                  ),
                                                ),
                                                Flexible(
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.darkGray
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      '${_endDate.year}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            fontSize:
                                                                ResponsiveFonts
                                                                    .getFontSize(
                                                                        context,
                                                                        9),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppTheme
                                                                .darkGray,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Período formatado embaixo
                                    Text(
                                      _formatPeriodDates(_startDate, _endDate),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.black,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Botão para ver resumo financeiro - em baixo
                            InkWell(
                              onTap: _showBalancePopup,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkGray.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.darkGray.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Ver Resumo Financeiro',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.black,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.open_in_new,
                                      color: AppTheme.darkGray.withOpacity(0.5),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Mostrar normalmente quando altura >= 700
                    return Column(
                      children: [
                        // Saldo e Período
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 24 : 12,
                            vertical: isDesktop ? 8 : 4,
                          ),
                          decoration: const BoxDecoration(
                            color: AppTheme.white,
                          ),
                          child: Row(
                            children: [
                              // Saldo - à esquerda
                              Expanded(
                                child: _SummaryCard(
                                  title: 'Saldo',
                                  value: formatCurrency(
                                      summary['gains']! - summary['expenses']!),
                                  color: AppTheme.darkGray,
                                  isFullWidth: true,
                                  isTall: true,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Período - à direita (agora ocupa todo o espaço)
                              Expanded(
                                child: InkWell(
                                  onTap: _selectPeriod,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            AppTheme.darkGray.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // "Período" e ano juntos na mesma linha
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                'Período',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: AppTheme.darkGray,
                                                    ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            if (_startDate.year ==
                                                _endDate.year)
                                              Flexible(
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.darkGray
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    '${_startDate.year}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontSize:
                                                              ResponsiveFonts
                                                                  .getFontSize(
                                                                      context,
                                                                      9),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              AppTheme.darkGray,
                                                        ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                            else
                                              Flexible(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Flexible(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppTheme
                                                              .darkGray
                                                              .withOpacity(0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                        ),
                                                        child: Text(
                                                          '${_startDate.year}',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontSize: ResponsiveFonts
                                                                        .getFontSize(
                                                                            context,
                                                                            9),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: AppTheme
                                                                        .darkGray,
                                                                  ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 2),
                                                      child: Text(
                                                        '-',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              fontSize:
                                                                  ResponsiveFonts
                                                                      .getFontSize(
                                                                          context,
                                                                          9),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: AppTheme
                                                                  .darkGray,
                                                            ),
                                                      ),
                                                    ),
                                                    Flexible(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppTheme
                                                              .darkGray
                                                              .withOpacity(0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                        ),
                                                        child: Text(
                                                          '${_endDate.year}',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontSize: ResponsiveFonts
                                                                        .getFontSize(
                                                                            context,
                                                                            9),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: AppTheme
                                                                        .darkGray,
                                                                  ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // Período formatado embaixo
                                        Text(
                                          _formatPeriodDates(
                                              _startDate, _endDate),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.black,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Ganhos e Despesas
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 24 : 12,
                            vertical: isDesktop ? 12 : 8,
                          ),
                          decoration: const BoxDecoration(
                            color: AppTheme.white,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Expanded(
                                child: _SummaryCard(
                                  title: 'Ganhos',
                                  value: formatCurrency(summary['gains']!),
                                  color: AppTheme.incomeGreen,
                                  count: _transactions
                                      .where((t) =>
                                          t.type == TransactionType.ganho)
                                      .length,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _SummaryCard(
                                  title: 'Despesas',
                                  value: formatCurrency(summary['expenses']!),
                                  color: AppTheme.expenseRed,
                                  count: _transactions
                                      .where((t) =>
                                          t.type == TransactionType.despesa)
                                      .length,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // Espaço para a barra de navegação
                SizedBox(
                  height: MediaQuery.of(context).padding.bottom > 0
                      ? MediaQuery.of(context).padding.bottom
                      : 40,
                ),
              ],
            ),
            // Overlay com blur quando o menu está aberto
            if (_isFabMenuExpanded)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isFabMenuExpanded = false;
                    });
                  },
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ),
                ),
              ),
            // Menu expandido (sobreposto a tudo)
            if (_isFabMenuExpanded)
              Positioned(
                top: isDesktop ? 88 : 68, // Altura do cabeçalho + padding
                right: isDesktop ? 24 : 12,
                child: _TopMenuExpanded(
                  onAddTransaction: _showAddTransactionDialog,
                  onImportTransactions: _showImportDialog,
                  onShowTransactions: () {
                    if (_showTransactions) {
                      setState(() {
                        _showTransactions = false;
                        _isFabMenuExpanded = false;
                      });
                    } else {
                      final screenWidth = MediaQuery.of(context).size.width;
                      if (screenWidth < 1300) {
                        _showTransactionsAsPopup();
                      } else {
                        setState(() {
                          _showTransactions = true;
                          _isFabMenuExpanded = false;
                        });
                      }
                    }
                  },
                  onShowHistory: () {
                    _showPeriodHistory();
                    setState(() {
                      _isFabMenuExpanded = false;
                    });
                  },
                  onLogout: () async {
                    // Mostrar diálogo de confirmação
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirmar Logout'),
                        content: const Text('Tem certeza que deseja sair?'),
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
                            child: const Text('Sair'),
                          ),
                        ],
                      ),
                    );

                    if (shouldLogout == true && mounted) {
                      await _authService.signOut();
                    }
                    if (mounted) {
                      setState(() {
                        _isFabMenuExpanded = false;
                      });
                    }
                  },
                  showTransactions: _showTransactions,
                  userName: _userName,
                  userEmail: _authService.currentUser?.email,
                  isLoadingUser: _isLoadingUser,
                  onToggle: () {
                    setState(() {
                      _isFabMenuExpanded = false;
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final int? count;
  final bool isFullWidth;
  final bool isTall;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    this.count,
    this.isFullWidth = false,
    this.isTall = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasBorder =
        !isFullWidth && (title == 'Ganhos' || title == 'Despesas');

    return Container(
      padding: EdgeInsets.all(isTall ? 12 : 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: hasBorder
            ? Border.all(
                color: color.withOpacity(0.3),
                width: 1,
              )
            : null,
      ),
      child: isFullWidth
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.darkGray,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: color,
                            fontSize: isTall
                                ? ResponsiveFonts.getFontSize(context, 18)
                                : null,
                          ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                ),
                if (count != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$count transações',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TopMenuExpanded extends StatefulWidget {
  final VoidCallback onAddTransaction;
  final VoidCallback onShowTransactions;
  final VoidCallback onShowHistory;
  final VoidCallback onLogout;
  final VoidCallback onToggle;
  final VoidCallback onImportTransactions;
  final bool showTransactions;
  final String? userName;
  final String? userEmail;
  final bool isLoadingUser;

  const _TopMenuExpanded({
    required this.onAddTransaction,
    required this.onShowTransactions,
    required this.onShowHistory,
    required this.onLogout,
    required this.onToggle,
    required this.onImportTransactions,
    required this.showTransactions,
    this.userName,
    this.userEmail,
    this.isLoadingUser = false,
  });

  @override
  State<_TopMenuExpanded> createState() => _TopMenuExpandedState();
}

class _TopMenuExpandedState extends State<_TopMenuExpanded>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(height: 12),
        // Botões de ação (aparecem quando expandido, flutuando acima)
        _buildActionButton(
          icon: Icons.history,
          label: 'Histórico',
          onTap: widget.onShowHistory,
          delay: 0,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: widget.showTransactions ? Icons.receipt_long : Icons.receipt,
          label: 'Transações',
          onTap: widget.onShowTransactions,
          delay: 2,
          isActive: widget.showTransactions,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.add,
          label: 'Adicionar',
          onTap: widget.onAddTransaction,
          delay: 3,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.upload_file,
          label: 'Importar',
          onTap: widget.onImportTransactions,
          delay: 4,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.logout,
          label: 'Sair',
          onTap: widget.onLogout,
          delay: 5,
          isDestructive: true,
        ),
        const SizedBox(height: 12),
        // Informações do usuário (abaixo dos botões)
        _buildUserInfo(),
      ],
    );
  }

  Widget _buildUserInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppTheme.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isLoadingUser)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              widget.userName ?? widget.userEmail ?? 'Usuário',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          if (widget.userName != null && widget.userEmail != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.userEmail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.darkGray,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required int delay,
    bool isActive = false,
    bool isDestructive = false,
  }) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            delay * 0.1,
            0.5 + (delay * 0.1),
            curve: Curves.easeOutBack,
          ),
        ),
      ),
      child: FadeTransition(
        opacity: _animationController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          isDestructive ? AppTheme.expenseRed : AppTheme.black,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            FloatingActionButton(
              heroTag: null,
              onPressed: onTap,
              backgroundColor: isDestructive
                  ? AppTheme.expenseRed
                  : (isActive ? AppTheme.darkGray : AppTheme.black),
              mini: true,
              child: Icon(icon, color: AppTheme.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportTransactionsDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const _ImportTransactionsDialog({required this.onImportComplete});

  @override
  State<_ImportTransactionsDialog> createState() =>
      _ImportTransactionsDialogState();
}

class _ImportTransactionsDialogState extends State<_ImportTransactionsDialog> {
  bool _isImporting = false;
  String? _errorMessage;
  String? _successMessage;

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
      // Converter dia da semana de string para número
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

  Future<void> _importFromFile() async {
    setState(() {
      _isImporting = true;
      _errorMessage = null;
      _successMessage = null;
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
          // Web: usar bytes
          fileContent = utf8.decode(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          // Outras plataformas: usar path
          final filePath = result.files.single.path!;
          fileContent = await File(filePath).readAsString();
        } else {
          throw Exception('Não foi possível ler o arquivo');
        }

        final jsonData = json.decode(fileContent) as List<dynamic>;

        final transactions =
            jsonData.map((e) => e as Map<String, dynamic>).toList();

        // Verificar duplicatas antes de importar
        final dbService = DatabaseService();
        final existingTransactions = await dbService.getAllTransactions();

        final duplicates = <Map<String, dynamic>>[];
        final duplicateIndices = <int>[];

        for (int i = 0; i < transactions.length; i++) {
          final tx = transactions[i];
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

        // Se houver duplicatas, mostrar diálogo com lista para seleção individual
        if (duplicates.isNotEmpty) {
          final selectedDuplicates = await showDialog<Set<int>>(
            context: context,
            builder: (context) => _DuplicateSelectionDialog(
              duplicates: duplicates,
              existingTransactions: existingTransactions,
            ),
          );

          if (selectedDuplicates == null) {
            // Usuário cancelou
            setState(() {
              _isImporting = false;
            });
            return;
          }

          // Processar apenas as duplicatas selecionadas
          if (selectedDuplicates.isNotEmpty) {
            // Sobrescrever: atualizar apenas as transações selecionadas
            final apiService = ApiService();
            for (var dup in duplicates) {
              final index = dup['index'] as int;
              if (!selectedDuplicates.contains(index)) {
                continue; // Pular se não foi selecionada
              }
              final tx = dup['transaction'] as Map<String, dynamic>;
              final existingId = dup['existingId'] as String;

              // Converter para Transaction e atualizar
              try {
                // Converter o JSON para Transaction (simplificado - usar a mesma lógica do backend)
                final amount = double.tryParse(
                        (tx['value'] ?? tx['amount'] ?? 0)
                            .toString()
                            .replaceAll(',', '.')) ??
                    0;
                DateTime? date;
                if (tx['date'] != null) {
                  date = DateTime.tryParse(tx['date'].toString());
                }
                date ??= DateTime.now();
                date = DateTime(date.year, date.month, date.day);

                String? frequency;
                int? dayOfWeek;
                int? dayOfMonth;
                if (tx['periodicity'] == 'mensal') {
                  frequency = 'monthly';
                  dayOfMonth = int.tryParse(tx['day']?.toString() ?? '');
                } else if (tx['periodicity'] == 'semanal') {
                  frequency = 'weekly';
                  final dayStr = (tx['dayofWeek'] ?? tx['day'] ?? '')
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
                  dayOfWeek = dayMap[dayStr];
                } else {
                  frequency = 'unique';
                }

                // Criar transação atualizada
                final updatedTx = Transaction(
                  id: existingId,
                  type: tx['type'] == 'ganho'
                      ? TransactionType.ganho
                      : TransactionType.despesa,
                  date: date,
                  description: tx['description']?.toString(),
                  amount: amount,
                  category: TransactionCategory.values.firstWhere(
                    (c) => c.name == tx['category']?.toString(),
                    orElse: () => TransactionCategory.miscelaneos,
                  ),
                  isSalary: tx['salary'] == true,
                  salaryAllocation: tx['salaryAllocation'] != null
                      ? SalaryAllocation(
                          gastosPercent: (tx['salaryAllocation']['gastos'] ??
                                  tx['salaryAllocation']['gastosPercent'] ??
                                  0)
                              .toDouble(),
                          lazerPercent: (tx['salaryAllocation']['lazer'] ??
                                  tx['salaryAllocation']['lazerPercent'] ??
                                  0)
                              .toDouble(),
                          poupancaPercent: (tx['salaryAllocation']
                                      ['poupanca'] ??
                                  tx['salaryAllocation']['poupancaPercent'] ??
                                  0)
                              .toDouble(),
                        )
                      : null,
                  expenseBudgetCategory: tx['budgetCategory'] != null
                      ? ExpenseBudgetCategory.values.firstWhere(
                          (c) => c.name == tx['budgetCategory']?.toString(),
                          orElse: () => ExpenseBudgetCategory.gastos,
                        )
                      : null,
                  frequency: frequency == 'monthly'
                      ? TransactionFrequency.monthly
                      : (frequency == 'weekly'
                          ? TransactionFrequency.weekly
                          : TransactionFrequency.unique),
                  dayOfWeek: dayOfWeek,
                  dayOfMonth: dayOfMonth,
                  person: tx['person']?.toString(),
                );

                await apiService.updateTransaction(updatedTx);
              } catch (e) {
                print('Erro ao atualizar transação duplicada: $e');
              }
            }

            // Remover todas as duplicatas (selecionadas e não selecionadas) da lista de importação
            final transactionsToImport = <Map<String, dynamic>>[];
            for (int i = 0; i < transactions.length; i++) {
              if (!duplicateIndices.contains(i)) {
                transactionsToImport.add(transactions[i]);
              }
            }

            final overwrittenCount = selectedDuplicates.length;
            final ignoredCount = duplicates.length - overwrittenCount;

            if (transactionsToImport.isNotEmpty) {
              final apiService = ApiService();
              final importResult =
                  await apiService.importBulkTransactions(transactionsToImport);

              if (mounted) {
                setState(() {
                  _isImporting = false;
                  String message = '';
                  if (overwrittenCount > 0) {
                    message = '$overwrittenCount transação(ões) atualizada(s)';
                  }
                  if (importResult['imported'] != null &&
                      (importResult['imported'] as int) > 0) {
                    if (message.isNotEmpty) message += ' e ';
                    message +=
                        '${importResult['imported']} nova(s) importada(s)';
                  }
                  if (ignoredCount > 0) {
                    if (message.isNotEmpty) message += ' (';
                    message += '$ignoredCount duplicata(s) ignorada(s)';
                    if (message.contains('(')) message += ')';
                  }
                  _successMessage =
                      message.isNotEmpty ? message : 'Importação concluída';
                });
              }
            } else {
              if (mounted) {
                setState(() {
                  _isImporting = false;
                  String message = '';
                  if (overwrittenCount > 0) {
                    message = '$overwrittenCount transação(ões) atualizada(s)';
                  }
                  if (ignoredCount > 0) {
                    if (message.isNotEmpty) message += ', ';
                    message += '$ignoredCount duplicata(s) ignorada(s)';
                  }
                  _successMessage = message.isNotEmpty
                      ? message
                      : 'Nenhuma transação nova para importar';
                });
              }
            }
          } else {
            // Nenhuma selecionada: remover todas as duplicatas da lista
            final transactionsToImport = <Map<String, dynamic>>[];
            for (int i = 0; i < transactions.length; i++) {
              if (!duplicateIndices.contains(i)) {
                transactionsToImport.add(transactions[i]);
              }
            }

            if (transactionsToImport.isNotEmpty) {
              final apiService = ApiService();
              final importResult =
                  await apiService.importBulkTransactions(transactionsToImport);

              if (mounted) {
                setState(() {
                  _isImporting = false;
                  _successMessage =
                      '${importResult['imported'] ?? 0} transação(ões) importada(s) (${duplicates.length} duplicata(s) ignorada(s))';
                });
              }
            } else {
              if (mounted) {
                setState(() {
                  _isImporting = false;
                  _successMessage =
                      'Nenhuma transação nova para importar (todas são duplicatas)';
                });
              }
            }
          }

          // Aguardar um pouco antes de fechar
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop();
            widget.onImportComplete();
          }
          return;
        }

        // Se não houver duplicatas, importar normalmente
        final apiService = ApiService();
        final importResult =
            await apiService.importBulkTransactions(transactions);

        if (mounted) {
          setState(() {
            _isImporting = false;
            _successMessage = importResult['message'] as String? ??
                '${importResult['imported']} transações importadas com sucesso';
          });

          // Se houver erros, mostrar diálogo de correção
          if (importResult['errors'] != null &&
              (importResult['errors'] as List).isNotEmpty) {
            final errors = importResult['errors'] as List<dynamic>;
            Navigator.of(context).pop(); // Fechar diálogo de importação

            // Mostrar diálogo de correção
            final fixed = await showDialog<List<Map<String, dynamic>>>(
              context: context,
              builder: (context) => _FixTransactionsDialog(
                errors: errors,
              ),
            );

            // Se o usuário corrigiu algumas transações, reenviar
            if (fixed != null && fixed.isNotEmpty) {
              try {
                final retryResult =
                    await apiService.importBulkTransactions(fixed);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(retryResult['message'] as String? ??
                          '${retryResult['imported']} transações corrigidas importadas com sucesso'),
                      backgroundColor: AppTheme.incomeGreen,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Erro ao reimportar transações corrigidas: $e'),
                      backgroundColor: AppTheme.expenseRed,
                    ),
                  );
                }
              }
            }

            widget.onImportComplete();
          } else {
            // Aguardar um pouco antes de fechar
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              Navigator.of(context).pop();
              widget.onImportComplete();
            }
          }
        }
      } else {
        setState(() {
          _isImporting = false;
        });
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
    return AlertDialog(
      title: const Text('Importar Transações'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.expenseRed),
              ),
            )
          else if (_successMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _successMessage!,
                style: const TextStyle(color: AppTheme.incomeGreen),
              ),
            )
          else
            const Text('Selecione um arquivo JSON para importar transações.'),
          if (!_isImporting &&
              _errorMessage == null &&
              _successMessage == null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _importFromFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Selecionar Arquivo JSON'),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isImporting && _successMessage == null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          )
        else if (_successMessage != null || _errorMessage != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
      ],
    );
  }
}

class _FixTransactionsDialog extends StatefulWidget {
  final List<dynamic> errors;

  const _FixTransactionsDialog({required this.errors});

  @override
  State<_FixTransactionsDialog> createState() => _FixTransactionsDialogState();
}

class _FixTransactionsDialogState extends State<_FixTransactionsDialog> {
  final Map<int, Map<String, dynamic>> _edits = {};

  @override
  void initState() {
    super.initState();
    // Inicializar com as transações originais
    for (var error in widget.errors) {
      final index = error['index'] as int;
      final tx = Map<String, dynamic>.from(error['transaction'] as Map);
      _edits[index] = tx;
    }
  }

  void _updateField(int index, String field, dynamic value) {
    setState(() {
      if (!_edits.containsKey(index)) {
        _edits[index] = Map<String, dynamic>.from(widget.errors
            .firstWhere((e) => e['index'] == index)['transaction']);
      }
      _edits[index]![field] = value;
    });
  }

  List<Map<String, dynamic>> _getFixedTransactions() {
    return _edits.values.where((tx) {
      // Validar se a transação está completa
      if (!tx.containsKey('type') || tx['type'] == null) return false;
      if (!tx.containsKey('category') || tx['category'] == null) return false;
      if (!tx.containsKey('value') && !tx.containsKey('amount')) return false;

      if (tx['periodicity'] == 'semanal') {
        if (!tx.containsKey('dayofWeek') && !tx.containsKey('day'))
          return false;
      } else if (tx['periodicity'] == 'mensal') {
        if (!tx.containsKey('day')) return false;
      }

      if (tx['type'] == 'despesa' && !tx.containsKey('budgetCategory'))
        return false;

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Corrigir Transações com Erro',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.errors.length} transação(ões) não foram importadas. Corrija os dados abaixo:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: widget.errors.length,
                itemBuilder: (context, index) {
                  final error = widget.errors[index];
                  final errorIndex = error['index'] as int;
                  final tx = _edits[errorIndex] ??
                      Map<String, dynamic>.from(error['transaction'] as Map);
                  final errorMsg = error['error'] as String;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transação ${errorIndex + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Erro: $errorMsg',
                            style: const TextStyle(
                              color: AppTheme.expenseRed,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Campos editáveis - mostrar todos os campos importantes
                          _buildField(
                            'Tipo',
                            tx['type'] ?? 'despesa',
                            ['ganho', 'despesa'],
                            (value) => _updateField(errorIndex, 'type', value),
                          ),
                          _buildTextField(
                            'Categoria',
                            tx['category'] ?? '',
                            (value) =>
                                _updateField(errorIndex, 'category', value),
                          ),
                          _buildNumberField(
                            'Valor',
                            (tx['value'] ?? tx['amount'] ?? '0').toString(),
                            (value) {
                              final numValue = double.tryParse(value) ?? 0;
                              _updateField(errorIndex, 'value', numValue);
                              _updateField(errorIndex, 'amount', numValue);
                            },
                          ),
                          if (tx['periodicity'] == 'semanal')
                            _buildField(
                              'Dia da Semana',
                              (tx['dayofWeek'] ?? tx['day'] ?? 'segunda')
                                  .toString(),
                              [
                                'domingo',
                                'segunda',
                                'terça',
                                'terca',
                                'quarta',
                                'quinta',
                                'sexta',
                                'sábado',
                                'sabado'
                              ],
                              (value) {
                                _updateField(errorIndex, 'dayofWeek', value);
                                _updateField(errorIndex, 'day', value);
                              },
                            ),
                          if (tx['periodicity'] == 'mensal')
                            _buildNumberField(
                              'Dia do Mês',
                              (tx['day'] ?? '1').toString(),
                              (value) => _updateField(
                                  errorIndex, 'day', int.tryParse(value) ?? 1),
                            ),
                          if ((tx['type'] ?? 'despesa') == 'despesa')
                            _buildField(
                              'Categoria de Orçamento',
                              tx['budgetCategory'] ?? 'gastos',
                              ['gastos', 'lazer', 'poupanca'],
                              (value) => _updateField(
                                  errorIndex, 'budgetCategory', value),
                            ),
                          if (tx['description'] != null)
                            _buildTextField(
                              'Descrição',
                              tx['description'] ?? '',
                              (value) => _updateField(
                                  errorIndex, 'description', value),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final fixed = _getFixedTransactions();
                    Navigator.of(context).pop(fixed);
                  },
                  child: Text(
                      'Importar ${_getFixedTransactions().length} Corrigida(s)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String value, List<String> options,
      Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: value,
            items: options
                .map((opt) => DropdownMenuItem(
                      value: opt,
                      child: Text(opt),
                    ))
                .toList(),
            onChanged: (val) => onChanged(val ?? value),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      String label, String value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField(
      String label, String value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _DuplicateSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> duplicates;
  final List<Transaction> existingTransactions;

  const _DuplicateSelectionDialog({
    required this.duplicates,
    required this.existingTransactions,
  });

  @override
  State<_DuplicateSelectionDialog> createState() =>
      _DuplicateSelectionDialogState();
}

class _DuplicateSelectionDialogState extends State<_DuplicateSelectionDialog> {
  final Set<int> _selectedIndices = {};

  String _formatTransaction(Map<String, dynamic> tx) {
    final type = tx['type'] == 'ganho' ? 'Ganho' : 'Despesa';
    final amount = tx['value'] ?? tx['amount'] ?? 0;
    final amountNum = (amount is num)
        ? amount.toDouble()
        : double.tryParse(amount.toString().replaceAll(',', '.')) ?? 0;
    final category = tx['category'] ?? '';
    final description = tx['description'] ?? '';
    final periodicity = tx['periodicity'] ?? '';

    String periodicityStr = '';
    if (periodicity == 'mensal') {
      periodicityStr = ' (Mensal, dia ${tx['day'] ?? ''})';
    } else if (periodicity == 'semanal') {
      periodicityStr = ' (Semanal, ${tx['dayofWeek'] ?? tx['day'] ?? ''})';
    }

    String desc = description.toString().isNotEmpty ? ' - $description' : '';

    return '$type: ${amountNum.toStringAsFixed(2)}€ - $category$periodicityStr$desc';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.all(16),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transações Duplicadas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selecione quais deseja sobrescrever (${widget.duplicates.length} encontrada(s))',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Lista de duplicatas
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: widget.duplicates.length,
                itemBuilder: (context, index) {
                  final dup = widget.duplicates[index];
                  final txIndex = dup['index'] as int;
                  final tx = dup['transaction'] as Map<String, dynamic>;
                  final isSelected = _selectedIndices.contains(txIndex);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      title: Text(
                        _formatTransaction(tx),
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIndices.add(txIndex);
                          } else {
                            _selectedIndices.remove(txIndex);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  );
                },
              ),
            ),
            // Botões
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botões de ação rápida
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedIndices.clear();
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Pular Todas',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedIndices.clear();
                            _selectedIndices.addAll(
                              widget.duplicates.map((d) => d['index'] as int),
                            );
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Selecionar Todas',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Botão Continuar (largura total)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_selectedIndices),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: Text('Continuar (${_selectedIndices.length})',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
