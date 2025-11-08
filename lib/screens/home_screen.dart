import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/budget_balances.dart';
import '../services/database.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../utils/date_utils.dart';
import '../widgets/calendar.dart';
import '../widgets/transaction_list.dart';
import '../widgets/add_transaction_dialog.dart';
import '../widgets/day_details_dialog.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  String? _userName;
  bool _isLoadingUser = true;

  int _selectedYear = DateTime.now().year;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  bool _showTransactions = false;
  List<Transaction> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Assume current year but don't set dates yet
    _selectedYear = DateTime.now().year;
    // Prompt for period selection after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectDateRangeOnStartup();
      _loadUserData();
    });
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

  Future<void> _selectDateRangeOnStartup() async {
    // Set default to current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);

    // Prompt user to select period
    await _selectDateRange();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    final transactions = await _databaseService.getTransactionsInRange(
      _startDate,
      _endDate,
    );
    setState(() {
      _transactions = transactions;
      _isLoading = false;
    });
  }

  Future<void> _selectYear() async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) {
        final currentYear = DateTime.now().year;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppTheme.black,
                  onPrimary: AppTheme.white,
                ),
          ),
          child: AlertDialog(
            title: const Text('Selecionar Ano'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ListView.builder(
                itemCount: 50,
                itemBuilder: (context, index) {
                  final year = currentYear - 25 + index;
                  return ListTile(
                    title: Text('$year'),
                    selected: year == _selectedYear,
                    onTap: () => Navigator.of(context).pop(year),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (picked != null && picked != _selectedYear) {
      setState(() {
        _selectedYear = picked;
        _updateDatesForYear();
      });
      await _loadTransactions();
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(_selectedYear - 10),
      lastDate: DateTime(_selectedYear + 10),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.black,
              onPrimary: AppTheme.white,
              secondary: AppTheme.white,
              onSecondary: AppTheme.white,
              surface: AppTheme.white,
              onSurface: AppTheme.black,
              error: AppTheme.expenseRed,
              onError: AppTheme.white,
            ),
            datePickerTheme: const DatePickerThemeData(
              backgroundColor: AppTheme.black,
              headerBackgroundColor: AppTheme.black,
              headerForegroundColor: AppTheme.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate =
            DateTime(picked.start.year, picked.start.month, picked.start.day);
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
      await _loadTransactions();
    }
  }

  void _updateDatesForYear() {
    // Por padrão, mostrar o mês atual do ano selecionado
    final now = DateTime.now();
    if (_selectedYear == now.year) {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
    } else {
      _startDate = DateTime(_selectedYear, 1, 1);
      _endDate = DateTime(_selectedYear, 1, 31);
    }
  }

  Future<void> _showAddTransactionDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => const AddTransactionDialog(),
    );

    if (result == true) {
      await _loadTransactions();
    }
  }

  Future<void> _showTransactionsAsPopup() async {
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
                    await _loadTransactions();
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
          balance += transaction.amount;

          // Calcular valores do salário
          if (transaction.isSalary) {
            final values = transaction.salaryValues;
            if (values != null) {
              gastos += values.gastos;
              lazer += values.lazer;
              poupanca += values.poupanca;
            }
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
        ),
      );
    }
  }

  Map<String, double> _calculateSummary() {
    double totalGains = 0.0;
    double totalExpenses = 0.0;

    for (var transaction in _transactions) {
      if (transaction.type == TransactionType.ganho) {
        totalGains += transaction.amount;
      } else {
        totalExpenses += transaction.amount;
      }
    }

    return {
      'gains': totalGains,
      'expenses': totalExpenses,
    };
  }

  @override
  Widget build(BuildContext context) {
    final summary = _calculateSummary();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppTheme.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'FinCal',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.account_circle),
                    onSelected: (value) async {
                      if (value == 'logout') {
                        // Mostrar diálogo de confirmação
                        final shouldLogout = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Confirmar Logout'),
                            content: const Text('Tem certeza que deseja sair?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
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
                      }
                    },
                    itemBuilder: (context) => [
                      // Informações do usuário
                      PopupMenuItem(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isLoadingUser)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              Text(
                                _userName ??
                                    _authService.currentUser?.email ??
                                    'Usuário',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            if (_userName != null &&
                                _authService.currentUser?.email != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _authService.currentUser!.email!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.darkGray,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            const Divider(),
                          ],
                        ),
                      ),
                      // Opção de logout
                      PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            const Icon(Icons.logout, color: AppTheme.black),
                            const SizedBox(width: 8),
                            const Text('Sair'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Conteúdo principal
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final screenWidth = constraints.maxWidth;
                          final usePopupForTransactions = screenWidth < 1300;

                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 800),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Calendário
                                  Expanded(
                                    flex: _showTransactions &&
                                            !usePopupForTransactions
                                        ? 2
                                        : 1,
                                    child: CalendarWidget(
                                      startDate: _startDate,
                                      endDate: _endDate,
                                      transactions: _transactions,
                                      onDayTap: _showDayDetails,
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
                                        onTransactionUpdated: _loadTransactions,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),

            // Controles (seletores e botões)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppTheme.white,
              ),
              child: Column(
                children: [
                  // Selectores
                  Row(
                    children: [
                      // Ano
                      Expanded(
                        child: _SelectorButton(
                          label: 'Ano',
                          value: _selectedYear.toString(),
                          onTap: _selectYear,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Período
                      Expanded(
                        child: _SelectorButton(
                          label: 'Período',
                          value:
                              '${formatDate(_startDate)} - ${formatDate(_endDate)}',
                          onTap: _selectDateRange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Botões de ação
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showAddTransactionDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar Transação'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (_showTransactions) {
                              setState(() {
                                _showTransactions = false;
                              });
                            } else {
                              // Verificar se deve mostrar como popup
                              final screenWidth =
                                  MediaQuery.of(context).size.width;
                              if (screenWidth < 1300) {
                                _showTransactionsAsPopup();
                              } else {
                                setState(() {
                                  _showTransactions = true;
                                });
                              }
                            }
                          },
                          icon: Icon(
                            _showTransactions
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          label: Text(_showTransactions
                              ? 'Ocultar Transações'
                              : 'Ver Transações'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _showTransactions
                                ? AppTheme.darkGray
                                : AppTheme.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Resumo mensal
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppTheme.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryCard(
                    title: 'Ganhos',
                    value: formatCurrency(summary['gains']!),
                    color: AppTheme.incomeGreen,
                    count: _transactions
                        .where((t) => t.type == TransactionType.ganho)
                        .length,
                  ),
                  _SummaryCard(
                    title: 'Despesas',
                    value: formatCurrency(summary['expenses']!),
                    color: AppTheme.expenseRed,
                    count: _transactions
                        .where((t) => t.type == TransactionType.despesa)
                        .length,
                  ),
                  _SummaryCard(
                    title: 'Saldo',
                    value: formatCurrency(
                        summary['gains']! - summary['expenses']!),
                    color: (summary['gains']! - summary['expenses']!) >= 0
                        ? AppTheme.incomeGreen
                        : AppTheme.expenseRed,
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

class _SelectorButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SelectorButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.black,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_drop_down, size: 24, color: AppTheme.black),
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

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
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
