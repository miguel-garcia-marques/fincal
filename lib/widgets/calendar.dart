import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/budget_balances.dart';
import '../utils/zeller_formula.dart';
import '../utils/date_utils.dart';
import '../utils/responsive_fonts.dart';
import '../theme/app_theme.dart';

class CalendarWidget extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final List<Transaction> transactions;
  final Function(DateTime) onDayTap;
  final String? filterPerson;

  const CalendarWidget({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.transactions,
    required this.onDayTap,
    this.filterPerson,
  });

  @override
  CalendarWidgetState createState() => _CalendarWidgetState();
}

abstract class CalendarWidgetState extends State<CalendarWidget> {
  void toggleView();
  void refreshCalendar() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _CalendarWidgetState extends CalendarWidgetState {
  late PageController _pageController;
  int _currentPageIndex = 0; // Índice da página atual (0 = primeiros 31 dias, 1 = próximos 31, etc.)
  static const int _daysPerPage = 31;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(CalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resetar página quando o período muda
    if (oldWidget.startDate != widget.startDate || 
        oldWidget.endDate != widget.endDate) {
      _currentPageIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPageIndex = index;
    });
  }

  void toggleView() {
    // Weekly view removed - no longer needed
  }

  List<Transaction> get _filteredTransactions {
    if (widget.filterPerson == null) {
      return widget.transactions;
    }

    if (widget.filterPerson == 'geral') {
      return widget.transactions
          .where((t) =>
              t.person == null || t.person == 'geral' || t.person!.isEmpty)
          .toList();
    }

    return widget.transactions
        .where((t) => t.person == widget.filterPerson)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final allDays = getDaysInRange(widget.startDate, widget.endDate);
    final weekDays = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

    // Debug: verificar se temos dias
    if (allDays.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            'Período inválido: ${widget.startDate} - ${widget.endDate}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    // Se houver mais de 31 dias, mostrar apenas a página atual (paginação real)
    List<DateTime> days;
    if (allDays.length > _daysPerPage) {
      final startIndex = _currentPageIndex * _daysPerPage;
      final endIndex = (startIndex + _daysPerPage).clamp(0, allDays.length);
      days = allDays.sublist(startIndex, endIndex);
      // Garantir que sempre temos pelo menos alguns dias
      if (days.isEmpty && allDays.isNotEmpty) {
        days = allDays.sublist(0, allDays.length.clamp(0, _daysPerPage));
        _currentPageIndex = 0; // Resetar índice se necessário
      }
    } else {
      days = allDays;
    }
    
    // Debug: garantir que temos dias após o cálculo
    if (days.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Erro: Nenhum dia calculado',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Total de dias: ${allDays.length}, Página: $_currentPageIndex',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    // Calcular saldos para TODOS os dias do período (não apenas os visíveis)
    // Isso garante que os saldos acumulados estejam corretos
    final Map<DateTime, double> dailyBalances = _calculateDailyBalances(allDays);
    final Map<DateTime, BudgetBalances> dailyBudgetBalances =
        _calculateDailyBudgetBalances(allDays);
    final Map<DateTime, List<Transaction>> dailyTransactions =
        _groupTransactionsByDay(allDays);

    // Para PageView, não precisamos organizar semanas aqui - será feito dentro do itemBuilder

    return LayoutBuilder(
      builder: (context, constraints) {
        // Obter altura total da tela
        final screenHeight = MediaQuery.of(context).size.height;

        // Calcular altura disponível para o calendário (altura do container menos padding e cabeçalho)
        const headerHeight = 60.0; // Altura reduzida do cabeçalho para dar mais espaço
        // Usar mais espaço disponível - reduzir menos do padding e header
        final availableHeight = constraints.maxHeight > 0 && constraints.maxHeight.isFinite
            ? constraints.maxHeight - headerHeight - 8
            : screenHeight * 0.75; // Aumentar fallback para usar mais espaço

        // Calcular altura dos dias dinamicamente
        // Para ecrãs pequenos, aumentar a altura mínima
        final isSmallScreen = screenHeight < 700;
        // Estimar número de semanas baseado nos dias (máximo 5 semanas para 31 dias)
        final estimatedWeeks = (days.length / 7).ceil().clamp(1, 6);
        final dayHeight = (availableHeight / estimatedWeeks).clamp(
            isSmallScreen ? 120.0 : 100.0,
            200.0); // Reduzir altura mínima para mostrar mais dias

        final hasMoreThan31Days = allDays.length > _daysPerPage;
        final totalPages = hasMoreThan31Days ? (allDays.length / _daysPerPage).ceil() : 1;
        
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.offWhite,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabeçalho com dias da semana
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: weekDays.map((day) {
                      return Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.black,
                                    ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                // Grid do calendário com paginação real usando PageView
                if (hasMoreThan31Days)
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      itemCount: totalPages,
                      itemBuilder: (context, pageIndex) {
                        // Calcular dias para esta página
                        final startIndex = pageIndex * _daysPerPage;
                        final endIndex = (startIndex + _daysPerPage).clamp(0, allDays.length);
                        final pageDays = allDays.sublist(startIndex, endIndex);
                        
                        return SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _buildCalendarGrid(pageDays, dailyBalances,
                                dailyBudgetBalances, dailyTransactions, context, dayHeight),
                          ),
                        );
                      },
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildCalendarGrid(days, dailyBalances,
                            dailyBudgetBalances, dailyTransactions, context, dayHeight),
                      ),
                    ),
                  ),
              ],
            ),
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

    // Agrupar semanas por mês para adicionar separadores
    // Para páginas subsequentes, precisamos determinar o último mês da página anterior
    List<Widget> weekWidgets = [];
    int? lastMonth;
    int? lastYear;
    
    // Se não é a primeira página, determinar o último mês da página anterior
    if (_currentPageIndex > 0) {
      final allDays = getDaysInRange(widget.startDate, widget.endDate);
      final prevPageStartIndex = (_currentPageIndex - 1) * _daysPerPage;
      if (prevPageStartIndex < allDays.length) {
        final prevPageEndIndex = (prevPageStartIndex + _daysPerPage).clamp(0, allDays.length);
        final prevPageDays = allDays.sublist(prevPageStartIndex, prevPageEndIndex);
        if (prevPageDays.isNotEmpty) {
          final lastDayOfPrevPage = prevPageDays.last;
          lastMonth = lastDayOfPrevPage.month;
          lastYear = lastDayOfPrevPage.year;
        }
      }
    }
    
    for (int i = 0; i < weeks.length; i++) {
      final week = weeks[i];
      
      // Encontrar todos os dias não-nulos da semana
      List<DateTime> weekDays = [];
      for (var day in week) {
        if (day != null) {
          weekDays.add(day);
        }
      }
      
      if (weekDays.isEmpty) {
        // Semana vazia, apenas adicionar sem separador
        weekWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: week.map((day) => const Expanded(child: SizedBox())).toList(),
            ),
          ),
        );
        continue;
      }
      
      // Ordenar dias da semana cronologicamente
      weekDays.sort((a, b) => a.compareTo(b));
      
      // Encontrar o primeiro e último dia da semana
      final firstDayOfWeek = weekDays.first;
      final lastDayOfWeek = weekDays.last;
      
      // Verificar se há algum dia de um novo mês nesta semana
      bool hasNewMonth = false;
      int? newMonth;
      int? newYear;
      
      for (var day in weekDays) {
        if (lastMonth == null) {
          // Primeira semana da página
          hasNewMonth = true;
          newMonth = day.month;
          newYear = day.year;
          break;
        } else if (day.month != lastMonth || day.year != lastYear) {
          // Encontramos um dia de um novo mês
          hasNewMonth = true;
          newMonth = day.month;
          newYear = day.year;
          break;
        }
      }
      
      // Verificar se esta semana cruza dois meses (semana mista)
      bool isMixedWeek = false;
      int? firstMonthInWeek;
      int? firstYearInWeek;
      int splitIndex = -1;
      
      if (hasNewMonth && newMonth != null && newYear != null && lastMonth != null) {
        // Verificar se o primeiro dia é do mês anterior e há dias do novo mês
        if (firstDayOfWeek.month != newMonth || firstDayOfWeek.year != newYear) {
          // Semana mista: começa com mês anterior e tem dias do novo mês
          isMixedWeek = true;
          firstMonthInWeek = firstDayOfWeek.month;
          firstYearInWeek = firstDayOfWeek.year;
          
          // Encontrar o índice onde o mês muda na semana
          for (int j = 0; j < week.length; j++) {
            final day = week[j];
            if (day != null && (day.month == newMonth && day.year == newYear)) {
              splitIndex = j;
              break;
            }
          }
        }
      }
      
      // Se encontramos um novo mês E o primeiro dia da semana é desse novo mês, adicionar separador
      if (hasNewMonth && newMonth != null && newYear != null && !isMixedWeek) {
        if (firstDayOfWeek.month == newMonth && firstDayOfWeek.year == newYear) {
          // O primeiro dia da semana é do novo mês - adicionar separador ANTES desta semana
          if (lastMonth == null) {
            // Primeira semana da página
            weekWidgets.add(_buildMonthSeparator(
              null, 
              null, 
              newMonth, 
              newYear
            ));
          } else {
            // Mês mudou
            weekWidgets.add(_buildMonthSeparator(
              lastMonth, 
              lastYear, 
              newMonth, 
              newYear
            ));
          }
          lastMonth = newMonth;
          lastYear = newYear;
        }
      }
      
      // Se é uma semana mista, dividir em duas partes com separador no meio
      if (isMixedWeek && splitIndex >= 0 && firstMonthInWeek != null && firstYearInWeek != null && newMonth != null && newYear != null) {
        // Primeira parte: dias do mês anterior
        final firstPartDays = week.sublist(0, splitIndex);
        final firstPartWidgets = firstPartDays.map((day) => _buildDayCell(day, dailyBalances, dailyBudgetBalances, dailyTransactions, context)).toList();
        // Adicionar espaços vazios para completar a linha
        firstPartWidgets.addAll(List.generate(7 - splitIndex, (_) => const Expanded(child: SizedBox())));
        
        weekWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: firstPartWidgets,
            ),
          ),
        );
        
        // Adicionar separador entre as duas partes
        weekWidgets.add(_buildMonthSeparator(
          firstMonthInWeek,
          firstYearInWeek,
          newMonth,
          newYear
        ));
        
        // Segunda parte: dias do novo mês
        final secondPartDays = week.sublist(splitIndex);
        final secondPartWidgets = <Widget>[];
        secondPartWidgets.addAll(List.generate(splitIndex, (_) => const Expanded(child: SizedBox())));
        secondPartWidgets.addAll(secondPartDays.map((day) => _buildDayCell(day, dailyBalances, dailyBudgetBalances, dailyTransactions, context)).toList());
        
        weekWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: secondPartWidgets,
            ),
          ),
        );
        
        lastMonth = newMonth;
        lastYear = newYear;
      } else {
        // Semana normal - adicionar normalmente
        // Atualizar último mês/ano com base no último dia da semana (mais recente)
        lastMonth = lastDayOfWeek.month;
        lastYear = lastDayOfWeek.year;
        
        // Adicionar a semana usando _buildDayCell
        weekWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: week.map((day) => _buildDayCell(day, dailyBalances, dailyBudgetBalances, dailyTransactions, context)).toList(),
            ),
          ),
        );
      }
    }
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: weekWidgets,
    );
  }

  Widget _buildDayCell(
    DateTime? day,
    Map<DateTime, double> dailyBalances,
    Map<DateTime, BudgetBalances> dailyBudgetBalances,
    Map<DateTime, List<Transaction>> dailyTransactions,
    BuildContext context,
  ) {
    if (day == null) {
      return const Expanded(child: SizedBox());
    }

    // Tentar encontrar o saldo usando diferentes chaves possíveis
    double? balance = dailyBalances[day];
    if (balance == null) {
      final dayUtc = DateTime.utc(day.year, day.month, day.day);
      balance = dailyBalances[dayUtc];
    }
    if (balance == null) {
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

    // Verificar se é o dia de hoje e se está no período
    final today = DateTime.now();
    final isToday = isSameDay(day, today);
    final todayNormalized = DateTime(today.year, today.month, today.day);
    final startNormalized = DateTime(widget.startDate.year, widget.startDate.month, widget.startDate.day);
    final endNormalized = DateTime(widget.endDate.year, widget.endDate.month, widget.endDate.day);
    final isTodayInPeriod = isToday && 
        (todayNormalized.isAfter(startNormalized) || isSameDay(todayNormalized, startNormalized)) &&
        (todayNormalized.isBefore(endNormalized) || isSameDay(todayNormalized, endNormalized));

    // Determinar tipo de transações do dia
    final hasGains = dayTransactions.any((t) => t.type == TransactionType.ganho);
    final hasExpenses = dayTransactions.any((t) => t.type == TransactionType.despesa);

    // Determinar cor baseada nos tipos de transações
    Color? dayColor;
    Color? borderColor;
    if (hasTransactions) {
      if (hasGains && !hasExpenses) {
        dayColor = AppTheme.incomeGreen.withOpacity(0.1);
        borderColor = AppTheme.incomeGreen;
      } else {
        dayColor = AppTheme.darkGray.withOpacity(0.2);
        borderColor = AppTheme.darkGray;
      }
    }

    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: _buildTooltipMessage(balance, budgetBalances, dayTransactions),
            child: GestureDetector(
              onTap: () => widget.onDayTap(day),
              child: Container(
                decoration: BoxDecoration(
                  color: dayColor ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: borderColor ?? Colors.transparent,
                    width: hasTransactions ? 2 : 0,
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppTheme.darkGray.withOpacity(0.1),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: Container(
                                width: double.infinity,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppTheme.darkGray.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    '${day.day}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.black,
                                      fontSize: ResponsiveFonts.getFontSize(context, 12),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppTheme.darkGray.withOpacity(0.1),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _formatBalanceForDay(balance),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.darkGray,
                                  fontSize: ResponsiveFonts.getFontSizeWithMin(context, 9, 8.5),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isTodayInPeriod)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.incomeGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.white,
                              width: 1.5,
                            ),
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
  }

  Widget _buildMonthSeparator(int? prevMonth, int? prevYear, int currentMonth, int currentYear) {
    // Separador minimalista entre meses
    // Usar nomes de meses em português diretamente em vez de DateFormat para evitar problemas de locale
    const monthNames = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    final monthName = monthNames[currentMonth - 1];
    
    return Builder(
      builder: (context) => Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Divider(
                thickness: 1,
                color: AppTheme.lighterGray.withOpacity(0.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '$monthName $currentYear',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.darkGray.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
              ),
            ),
            Expanded(
              child: Divider(
                thickness: 1,
                color: AppTheme.lighterGray.withOpacity(0.5),
              ),
            ),
          ],
        ),
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

  String _formatBalanceForDay(double balance) {
    // Se o valor for muito grande (>= 1000), arredondar e mostrar inteiro
    if (balance.abs() >= 1000) {
      return balance.round().toString();
    }
    // Caso contrário, mostrar com 2 decimais mas sem símbolo do euro
    return balance.toStringAsFixed(2);
  }

  Map<DateTime, double> _calculateDailyBalances(List<DateTime> days) {
    Map<DateTime, double> balances = {};
    double runningBalance = 0.0;
    final transactions = _filteredTransactions;

    if (transactions.isEmpty) {
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
            if (transaction.isSalary && transaction.salaryValues != null) {
              // Para salários, adicionar o valor total mas subtrair a poupança (que é despesa)
              final poupancaAmount = transaction.salaryValues!.poupanca;
              runningBalance += transaction.amount - poupancaAmount;
            } else {
              runningBalance += transaction.amount;
            }
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
    final transactions = _filteredTransactions;

    for (var transaction in transactions) {
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
    final transactions = _filteredTransactions;

    // Ordenar transações por data
    final sortedTransactions = List<Transaction>.from(transactions)
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
              // Poupança é considerada despesa, então subtrair em vez de adicionar
              poupanca -= values.poupanca;
            }
          } else if (transaction.type == TransactionType.ganho &&
              transaction.category == TransactionCategory.alimentacao) {
            // Ganhos de alimentação entram como valor positivo em "gastos"
            gastos += transaction.amount;
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
