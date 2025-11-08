import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/budget_balances.dart';
import '../utils/zeller_formula.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';

class CalendarWidget extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final List<Transaction> transactions;
  final Function(DateTime) onDayTap;

  const CalendarWidget({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.transactions,
    required this.onDayTap,
  });

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends State<CalendarWidget> {
  int _currentWeekIndex = 0;
  bool? _manualViewOverride; // null = auto, true = weekly, false = monthly
  static const double _heightReduction =
      150.0; // Valor a subtrair da altura disponível para calcular threshold

  bool _shouldUseWeeklyView(
      double availableHeight, int weeksCount, double screenHeight) {
    if (_manualViewOverride != null) {
      return _manualViewOverride!;
    }
    // Auto: calcular threshold como altura da janela total menos um valor fixo
    // Se a altura disponível for menor que o threshold, usar vista semanal
    const threshold = _heightReduction;

    // Se a altura disponível for menor que o threshold, usar vista semanal
    // Se for maior ou igual, usar vista mensal
    return availableHeight < threshold;
  }

  @override
  Widget build(BuildContext context) {
    final days = getDaysInRange(widget.startDate, widget.endDate);
    final weekDays = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

    // Organizar dias por semanas
    final weeks = _organizeDaysIntoWeeks(days);

    // Calcular saldo disponível para cada dia
    final Map<DateTime, double> dailyBalances = _calculateDailyBalances(days);
    final Map<DateTime, BudgetBalances> dailyBudgetBalances =
        _calculateDailyBudgetBalances(days);
    final Map<DateTime, List<Transaction>> dailyTransactions =
        _groupTransactionsByDay(days);

    // Resetar índice se mudou para weekly view
    if (_currentWeekIndex >= weeks.length && weeks.isNotEmpty) {
      _currentWeekIndex = 0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Obter altura total da tela
        final screenHeight = MediaQuery.of(context).size.height;

        // Calcular altura disponível para o calendário (altura do container menos padding e cabeçalho)
        const headerHeight = 80.0; // Altura aproximada do cabeçalho
        final navigationHeight =
            weeks.isNotEmpty ? 60.0 : 0.0; // Altura da navegação semanal
        final availableHeight = constraints.maxHeight -
            headerHeight -
            navigationHeight -
            48; // 48 = padding

        // Determinar se deve usar vista semanal baseado no espaço disponível
        final useWeeklyView =
            _shouldUseWeeklyView(availableHeight, weeks.length, screenHeight);

        // Calcular altura dos dias dinamicamente
        final dayHeight = useWeeklyView
            ? (availableHeight / 1.3)
                .clamp(150.0, 300.0) // Vista semanal: mais alto
            : (availableHeight / weeks.length.clamp(1, 6))
                .clamp(80.0, 150.0); // Vista mensal: dividir pelas semanas

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho com botão de toggle e dias da semana
              Row(
                children: [
                  // Botão de toggle de vista
                  IconButton(
                    icon: Icon(
                      useWeeklyView
                          ? Icons.calendar_view_month
                          : Icons.calendar_view_week,
                      color: AppTheme.black,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_manualViewOverride == null) {
                          // Se estava em auto, forçar para a vista oposta
                          _manualViewOverride = !useWeeklyView;
                        } else {
                          // Se estava manual, alternar
                          _manualViewOverride = !_manualViewOverride!;
                        }
                        if (_manualViewOverride == true &&
                            _currentWeekIndex >= weeks.length) {
                          _currentWeekIndex = 0;
                        }
                      });
                    },
                    tooltip: useWeeklyView ? 'Vista Mensal' : 'Vista Semanal',
                  ),
                  const SizedBox(width: 8),
                  // Cabeçalho com dias da semana
                  Expanded(
                    child: Row(
                      children: weekDays.map((day) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.black,
                                  ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Navegação semanal (se usar vista semanal)
              if (useWeeklyView && weeks.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _currentWeekIndex > 0
                          ? () => setState(() => _currentWeekIndex--)
                          : null,
                    ),
                    Text(
                      'Semana ${_currentWeekIndex + 1} de ${weeks.length}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentWeekIndex < weeks.length - 1
                          ? () => setState(() => _currentWeekIndex++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // Grid do calendário
              Expanded(
                child: useWeeklyView && weeks.isNotEmpty
                    ? _buildWeekView(
                        weeks[_currentWeekIndex.clamp(0, weeks.length - 1)],
                        dailyBalances,
                        dailyBudgetBalances,
                        dailyTransactions,
                        context,
                        dayHeight,
                      )
                    : _buildCalendarGrid(
                        days,
                        dailyBalances,
                        dailyBudgetBalances,
                        dailyTransactions,
                        context,
                        dayHeight),
              ),
            ],
          ),
        );
      },
    );
  }

  List<List<DateTime?>> _organizeDaysIntoWeeks(List<DateTime> days) {
    List<List<DateTime?>> weeks = [];

    if (days.isEmpty) {
      return weeks;
    }

    int getCalendarIndex(DateTime date) {
      int zeller = getDayOfWeek(date);
      return (zeller == 1)
          ? 0
          : (zeller == 0)
              ? 6
              : zeller - 1;
    }

    final uniqueDays = <DateTime>{};
    for (var day in days) {
      uniqueDays.add(DateTime(day.year, day.month, day.day));
    }
    final sortedDays = uniqueDays.toList()..sort((a, b) => a.compareTo(b));

    final dayMap = <String, DateTime>{};
    for (var day in sortedDays) {
      final key = '${day.year}-${day.month}-${day.day}';
      dayMap[key] = day;
    }

    if (sortedDays.isEmpty) return weeks;

    final firstDay = sortedDays.first;
    final lastDay = sortedDays.last;

    final firstDayIndex = getCalendarIndex(firstDay);
    final daysToSubtract = firstDayIndex;
    final weekStart = firstDay.subtract(Duration(days: daysToSubtract));

    final lastDayIndex = getCalendarIndex(lastDay);
    final daysToAdd = 6 - lastDayIndex;
    final weekEnd = lastDay.add(Duration(days: daysToAdd));

    DateTime currentDate = weekStart;
    List<DateTime?> currentWeek = List.filled(7, null);

    while (currentDate.isBefore(weekEnd) ||
        currentDate.isAtSameMomentAs(weekEnd)) {
      final dayIndex = getCalendarIndex(currentDate);
      final dateKey =
          '${currentDate.year}-${currentDate.month}-${currentDate.day}';

      if (dayMap.containsKey(dateKey)) {
        currentWeek[dayIndex] = dayMap[dateKey]!;
      }

      if (dayIndex == 6) {
        if (currentWeek.any((d) => d != null)) {
          weeks.add(List.from(currentWeek));
        }
        currentWeek = List.filled(7, null);
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    if (currentWeek.any((d) => d != null)) {
      weeks.add(currentWeek);
    }

    return weeks;
  }

  Widget _buildWeekView(
    List<DateTime?> week,
    Map<DateTime, double> dailyBalances,
    Map<DateTime, BudgetBalances> dailyBudgetBalances,
    Map<DateTime, List<Transaction>> dailyTransactions,
    BuildContext context,
    double dayHeight,
  ) {
    return Row(
      children: week.map((day) {
        if (day == null) {
          return const Expanded(child: SizedBox());
        }

        // Tentar encontrar o saldo usando diferentes chaves possíveis
        double? balance = dailyBalances[day];
        if (balance == null) {
          // Tentar com UTC
          final dayUtc = DateTime.utc(day.year, day.month, day.day);
          balance = dailyBalances[dayUtc];
        }
        if (balance == null) {
          // Tentar com local
          final dayLocal = DateTime(day.year, day.month, day.day);
          balance = dailyBalances[dayLocal];
        }
        balance ??= 0.0;

        BudgetBalances? budgetBalances = dailyBudgetBalances[day];
        if (budgetBalances == null) {
          final dayUtc = DateTime.utc(day.year, day.month, day.day);
          budgetBalances = dailyBudgetBalances[dayUtc];
        }
        if (budgetBalances == null) {
          final dayLocal = DateTime(day.year, day.month, day.day);
          budgetBalances = dailyBudgetBalances[dayLocal];
        }

        List<Transaction> dayTransactions = dailyTransactions[day] ?? [];
        if (dayTransactions.isEmpty) {
          final dayUtc = DateTime.utc(day.year, day.month, day.day);
          dayTransactions = dailyTransactions[dayUtc] ?? [];
        }
        if (dayTransactions.isEmpty) {
          final dayLocal = DateTime(day.year, day.month, day.day);
          dayTransactions = dailyTransactions[dayLocal] ?? [];
        }
        final hasTransactions = dayTransactions.isNotEmpty;

        // Determinar tipo de transações do dia
        final hasGains =
            dayTransactions.any((t) => t.type == TransactionType.ganho);
        final hasExpenses =
            dayTransactions.any((t) => t.type == TransactionType.despesa);

        // Determinar cor baseada nos tipos de transações
        Color? dayColor;
        Color? borderColor;
        if (hasTransactions) {
          if (hasGains && !hasExpenses) {
            // Verde: apenas ganhos
            dayColor = AppTheme.incomeGreen.withOpacity(0.1);
            borderColor = AppTheme.incomeGreen;
          } else {
            // Cinzento escuro: apenas despesas ou ambos
            dayColor = AppTheme.darkGray.withOpacity(0.2);
            borderColor = AppTheme.darkGray;
          }
        }

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: _buildTooltipMessage(
                  balance, budgetBalances, dayTransactions),
              child: GestureDetector(
                onTap: () => widget.onDayTap(day),
                child: Container(
                  height: dayHeight,
                  decoration: BoxDecoration(
                    color: dayColor ?? AppTheme.lighterGray.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor ?? Colors.transparent,
                      width: hasTransactions ? 2 : 0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${day.day}',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.black,
                                    fontSize: 16,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatCurrency(balance),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: hasTransactions
                                        ? (hasGains && !hasExpenses
                                            ? AppTheme.incomeGreen
                                            : AppTheme.darkGray)
                                        : AppTheme.darkGray,
                                    fontSize: 13,
                                  ),
                        ),
                        if (dayTransactions.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${dayTransactions.length} ${dayTransactions.length == 1 ? 'transação' : 'transações'}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: AppTheme.darkGray,
                                      fontWeight: FontWeight.w400,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarGrid(
    List<DateTime> days,
    Map<DateTime, double> dailyBalances,
    Map<DateTime, BudgetBalances> dailyBudgetBalances,
    Map<DateTime, List<Transaction>> dailyTransactions,
    BuildContext context,
    double dayHeight,
  ) {
    // Organizar dias por semanas
    // Zeller: 0=Sáb, 1=Dom, 2=Seg, 3=Ter, 4=Qua, 5=Qui, 6=Sex
    // Calendário: Dom=0, Seg=1, Ter=2, Qua=3, Qui=4, Sex=5, Sáb=6
    List<List<DateTime?>> weeks = [];

    if (days.isEmpty) {
      return const SizedBox();
    }

    // Converter Zeller para índice do calendário (Dom=0, Seg=1, ..., Sáb=6)
    int getCalendarIndex(DateTime date) {
      int zeller = getDayOfWeek(date);
      return (zeller == 1)
          ? 0
          : (zeller == 0)
              ? 6
              : zeller - 1;
    }

    // Usar os dias originais da lista (não criar novas instâncias)
    // Criar mapa de dias por chave para lookup rápido usando as instâncias originais
    final dayMap = <String, DateTime>{};
    for (var day in days) {
      final key = '${day.year}-${day.month}-${day.day}';
      // Se já existe, manter a primeira instância (que é a chave do mapa de saldos)
      if (!dayMap.containsKey(key)) {
        dayMap[key] = day;
      }
    }

    // Ordenar os dias únicos
    final sortedDays = dayMap.values.toList()..sort((a, b) => a.compareTo(b));

    // Encontrar o primeiro e último dia
    if (sortedDays.isEmpty) return const SizedBox();

    final firstDay = sortedDays.first;
    final lastDay = sortedDays.last;

    // Encontrar o domingo da semana do primeiro dia
    final firstDayIndex = getCalendarIndex(firstDay);
    final daysToSubtract = firstDayIndex;
    final weekStart = firstDay.subtract(Duration(days: daysToSubtract));

    // Encontrar o sábado da semana do último dia
    final lastDayIndex = getCalendarIndex(lastDay);
    final daysToAdd = 6 - lastDayIndex;
    final weekEnd = lastDay.add(Duration(days: daysToAdd));

    // Criar todas as semanas necessárias
    DateTime currentDate = weekStart;
    List<DateTime?> currentWeek = List.filled(7, null);

    while (currentDate.isBefore(weekEnd) ||
        currentDate.isAtSameMomentAs(weekEnd)) {
      final dayIndex = getCalendarIndex(currentDate);
      final dateKey =
          '${currentDate.year}-${currentDate.month}-${currentDate.day}';

      // Se este dia está na lista, adicionar à semana
      if (dayMap.containsKey(dateKey)) {
        currentWeek[dayIndex] = dayMap[dateKey]!;
      }

      // Se chegamos ao sábado, finalizar a semana
      if (dayIndex == 6) {
        // Só adicionar a semana se tiver pelo menos um dia
        if (currentWeek.any((d) => d != null)) {
          weeks.add(List.from(currentWeek));
        }
        currentWeek = List.filled(7, null);
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    // Adicionar última semana se não estiver vazia e não foi adicionada
    if (currentWeek.any((d) => d != null)) {
      weeks.add(currentWeek);
    }

    return SingleChildScrollView(
      child: Column(
        children: weeks.map((week) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: week.map((day) {
                if (day == null) {
                  return const Expanded(child: SizedBox());
                }

                // Tentar encontrar o saldo usando diferentes chaves possíveis
                double? balance = dailyBalances[day];
                if (balance == null) {
                  // Tentar com UTC
                  final dayUtc = DateTime.utc(day.year, day.month, day.day);
                  balance = dailyBalances[dayUtc];
                }
                if (balance == null) {
                  // Tentar com local
                  final dayLocal = DateTime(day.year, day.month, day.day);
                  balance = dailyBalances[dayLocal];
                }
                balance ??= 0.0;

                BudgetBalances? budgetBalances = dailyBudgetBalances[day];
                if (budgetBalances == null) {
                  final dayUtc = DateTime.utc(day.year, day.month, day.day);
                  budgetBalances = dailyBudgetBalances[dayUtc];
                }
                if (budgetBalances == null) {
                  final dayLocal = DateTime(day.year, day.month, day.day);
                  budgetBalances = dailyBudgetBalances[dayLocal];
                }

                List<Transaction> dayTransactions =
                    dailyTransactions[day] ?? [];
                if (dayTransactions.isEmpty) {
                  final dayUtc = DateTime.utc(day.year, day.month, day.day);
                  dayTransactions = dailyTransactions[dayUtc] ?? [];
                }
                if (dayTransactions.isEmpty) {
                  final dayLocal = DateTime(day.year, day.month, day.day);
                  dayTransactions = dailyTransactions[dayLocal] ?? [];
                }
                final hasTransactions = dayTransactions.isNotEmpty;

                // Determinar tipo de transações do dia
                final hasGains =
                    dayTransactions.any((t) => t.type == TransactionType.ganho);
                final hasExpenses = dayTransactions
                    .any((t) => t.type == TransactionType.despesa);

                // Determinar cor baseada nos tipos de transações
                Color? dayColor;
                Color? borderColor;
                if (hasTransactions) {
                  if (hasGains && !hasExpenses) {
                    // Verde: apenas ganhos
                    dayColor = AppTheme.incomeGreen.withOpacity(0.1);
                    borderColor = AppTheme.incomeGreen;
                  } else {
                    // Cinzento escuro: apenas despesas ou ambos
                    dayColor = AppTheme.darkGray.withOpacity(0.2);
                    borderColor = AppTheme.darkGray;
                  }
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: _buildTooltipMessage(
                          balance, budgetBalances, dayTransactions),
                      child: GestureDetector(
                        onTap: () => widget.onDayTap(day),
                        child: Container(
                          height: dayHeight,
                          decoration: BoxDecoration(
                            color: dayColor ??
                                AppTheme.lighterGray.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: borderColor ?? Colors.transparent,
                              width: hasTransactions ? 2 : 0,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${day.day}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.black,
                                        fontSize: 14,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          formatCurrency(balance),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: hasTransactions
                                                    ? (hasGains && !hasExpenses
                                                        ? AppTheme.incomeGreen
                                                        : AppTheme.darkGray)
                                                    : AppTheme.darkGray,
                                                fontSize: 11,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _buildTooltipMessage(
    double balance,
    BudgetBalances? budgetBalances,
    List<Transaction> dayTransactions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('Saldo: ${formatCurrency(balance)}');

    if (budgetBalances != null &&
        (budgetBalances.gastos != 0 ||
            budgetBalances.lazer != 0 ||
            budgetBalances.poupanca != 0)) {
      buffer.writeln('');
      buffer.writeln('Orçamento:');
      if (budgetBalances.gastos != 0) {
        buffer.writeln('Gastos: ${formatCurrency(budgetBalances.gastos)}');
      }
      if (budgetBalances.lazer != 0) {
        buffer.writeln('Lazer: ${formatCurrency(budgetBalances.lazer)}');
      }
      if (budgetBalances.poupanca != 0) {
        buffer.writeln('Poupança: ${formatCurrency(budgetBalances.poupanca)}');
      }
    }

    if (dayTransactions.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln(
          '${dayTransactions.length} ${dayTransactions.length == 1 ? 'transação' : 'transações'}');
    }

    return buffer.toString().trim();
  }

  Map<DateTime, double> _calculateDailyBalances(List<DateTime> days) {
    Map<DateTime, double> balances = {};
    double runningBalance = 0.0;

    if (widget.transactions.isEmpty) {
      // Se não há transações, retornar saldo zero para todos os dias
      for (var day in days) {
        balances[day] = 0.0;
      }
      return balances;
    }

    // Ordenar transações por data
    final sortedTransactions = List<Transaction>.from(widget.transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    int transactionIndex = 0;

    for (var day in days) {
      // Normalizar o dia para UTC para comparação consistente
      final currentDay = DateTime.utc(day.year, day.month, day.day);

      // Processar todas as transações deste dia ou anteriores
      while (transactionIndex < sortedTransactions.length) {
        final transaction = sortedTransactions[transactionIndex];
        // Normalizar a data da transação para UTC para comparação
        final transactionDate = DateTime.utc(
          transaction.date.year,
          transaction.date.month,
          transaction.date.day,
        );

        if (transactionDate.isAfter(currentDay)) {
          break;
        }

        if (transactionDate.isBefore(currentDay) ||
            (transactionDate.year == currentDay.year &&
                transactionDate.month == currentDay.month &&
                transactionDate.day == currentDay.day)) {
          if (transaction.type == TransactionType.ganho) {
            runningBalance += transaction.amount;
          } else {
            runningBalance -= transaction.amount;
          }
          transactionIndex++;
        } else {
          break;
        }
      }

      // Usar o dia original como chave (não criar nova instância)
      balances[day] = runningBalance;
    }

    return balances;
  }

  Map<DateTime, List<Transaction>> _groupTransactionsByDay(
      List<DateTime> days) {
    Map<DateTime, List<Transaction>> grouped = {};

    for (var transaction in widget.transactions) {
      // Normalizar a data da transação para UTC
      final transactionDate = DateTime.utc(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );

      // Encontrar o dia correspondente na lista de dias
      for (var day in days) {
        final dayUtc = DateTime.utc(day.year, day.month, day.day);
        if (transactionDate.year == dayUtc.year &&
            transactionDate.month == dayUtc.month &&
            transactionDate.day == dayUtc.day) {
          // Usar o dia original da lista (pode ser UTC ou local) como chave
          grouped.putIfAbsent(day, () => []).add(transaction);
          break;
        }
      }
    }

    return grouped;
  }

  Map<DateTime, BudgetBalances> _calculateDailyBudgetBalances(
      List<DateTime> days) {
    Map<DateTime, BudgetBalances> balances = {};
    double gastos = 0.0;
    double lazer = 0.0;
    double poupanca = 0.0;

    // Ordenar transações por data
    final sortedTransactions = List<Transaction>.from(widget.transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    int transactionIndex = 0;

    for (var day in days) {
      // Normalizar o dia para UTC para comparação consistente
      final currentDay = DateTime.utc(day.year, day.month, day.day);

      // Processar todas as transações deste dia ou anteriores
      while (transactionIndex < sortedTransactions.length) {
        final transaction = sortedTransactions[transactionIndex];
        // Normalizar a data da transação para UTC para comparação
        final transactionDate = DateTime.utc(
          transaction.date.year,
          transaction.date.month,
          transaction.date.day,
        );

        if (transactionDate.isAfter(currentDay)) {
          break;
        }

        if (transactionDate.isBefore(currentDay) ||
            (transactionDate.year == currentDay.year &&
                transactionDate.month == currentDay.month &&
                transactionDate.day == currentDay.day)) {
          if (transaction.type == TransactionType.ganho &&
              transaction.isSalary) {
            // Adicionar valores do salário
            final values = transaction.salaryValues;
            if (values != null) {
              gastos += values.gastos;
              lazer += values.lazer;
              poupanca += values.poupanca;
            }
          } else if (transaction.type == TransactionType.despesa) {
            // Deduzir da categoria correspondente
            final amount = transaction.amount;
            switch (transaction.expenseBudgetCategory) {
              case ExpenseBudgetCategory.gastos:
                gastos -= amount;
                break;
              case ExpenseBudgetCategory.lazer:
                lazer -= amount;
                break;
              case ExpenseBudgetCategory.poupanca:
                poupanca -= amount;
                break;
              case null:
                break;
            }
          }
          transactionIndex++;
        } else {
          break;
        }
      }

      balances[day] = BudgetBalances(
        gastos: gastos,
        lazer: lazer,
        poupanca: poupanca,
      );
    }

    return balances;
  }
}
