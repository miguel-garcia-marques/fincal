import 'package:flutter/material.dart';
import '../utils/zeller_formula.dart';
import '../theme/app_theme.dart';

class CustomCalendarPicker extends StatefulWidget {
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final int initialYear;

  const CustomCalendarPicker({
    super.key,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.initialYear,
  });

  @override
  State<CustomCalendarPicker> createState() => _CustomCalendarPickerState();
}

class _CustomCalendarPickerState extends State<CustomCalendarPicker> {
  late DateTime _currentMonth;
  late DateTime? _selectedStartDate;
  late DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialYear, widget.initialStartDate.month, 1);
    _selectedStartDate = widget.initialStartDate;
    _selectedEndDate = widget.initialEndDate;
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  void _onDayTap(DateTime date) {
    setState(() {
      if (_selectedStartDate == null || 
          (_selectedStartDate != null && _selectedEndDate != null)) {
        // Nova seleção: começar do zero
        _selectedStartDate = date;
        _selectedEndDate = null;
      } else if (_selectedStartDate != null && _selectedEndDate == null) {
        // Completar a seleção
        final startOnly = DateTime(_selectedStartDate!.year, _selectedStartDate!.month, _selectedStartDate!.day);
        final dateOnly = DateTime(date.year, date.month, date.day);
        
        if (dateOnly.isBefore(startOnly)) {
          // Se clicou numa data anterior, trocar
          _selectedEndDate = _selectedStartDate;
          _selectedStartDate = date;
        } else {
          _selectedEndDate = date;
        }
      }
      
      // Se a data selecionada está em outro mês, navegar para esse mês
      if (date.month != _currentMonth.month || date.year != _currentMonth.year) {
        _currentMonth = DateTime(date.year, date.month, 1);
      }
    });
  }

  bool _isDateStartOrEnd(DateTime date) {
    if (_selectedStartDate == null) return false;
    if (_selectedEndDate == null) {
      return date.year == _selectedStartDate!.year &&
          date.month == _selectedStartDate!.month &&
          date.day == _selectedStartDate!.day;
    }
    
    final start = _selectedStartDate!;
    final end = _selectedEndDate!;
    
    return (date.year == start.year && date.month == start.month && date.day == start.day) ||
        (date.year == end.year && date.month == end.month && date.day == end.day);
  }

  bool _isDateInMiddleRange(DateTime date) {
    if (_selectedStartDate == null || _selectedEndDate == null) return false;
    
    final start = _selectedStartDate!;
    final end = _selectedEndDate!;
    
    final dateOnly = DateTime(date.year, date.month, date.day);
    final startOnly = DateTime(start.year, start.month, start.day);
    final endOnly = DateTime(end.year, end.month, end.day);
    
    // Verificar se a data está entre start e end (exclusivo)
    if (startOnly.isBefore(endOnly)) {
      return dateOnly.isAfter(startOnly) && dateOnly.isBefore(endOnly);
    } else {
      // Se end é antes de start (não deveria acontecer, mas por segurança)
      return dateOnly.isAfter(endOnly) && dateOnly.isBefore(startOnly);
    }
  }

  bool _isDateSelected(DateTime date) {
    return _isDateStartOrEnd(date) || _isDateInMiddleRange(date);
  }

  bool _isPreviousDaySelected(DateTime date, List<DateTime?> allDays, int currentIndex) {
    // Verificar se o dia anterior no calendário (não no grid) está selecionado
    final previousDay = date.subtract(const Duration(days: 1));
    // Verificar se está no mesmo mês
    if (previousDay.year == date.year && previousDay.month == date.month) {
      return _isDateSelected(previousDay);
    }
    // Se não está no mesmo mês, verificar se o dia anterior no grid está selecionado
    if (currentIndex > 0 && allDays[currentIndex - 1] != null) {
      final prevDate = allDays[currentIndex - 1]!;
      // Verificar se são dias consecutivos (prevDate deve ser anterior a date)
      final daysDiff = date.difference(prevDate).inDays;
      if (daysDiff == 1 && prevDate.isBefore(date)) {
        return _isDateSelected(prevDate);
      }
    }
    return false;
  }

  bool _isNextDaySelected(DateTime date, List<DateTime?> allDays, int currentIndex) {
    // Verificar se o próximo dia no calendário (não no grid) está selecionado
    final nextDay = date.add(const Duration(days: 1));
    // Verificar se está no mesmo mês
    if (nextDay.year == date.year && nextDay.month == date.month) {
      return _isDateSelected(nextDay);
    }
    // Se não está no mesmo mês, verificar se o próximo dia no grid está selecionado
    if (currentIndex < allDays.length - 1 && allDays[currentIndex + 1] != null) {
      final nextDate = allDays[currentIndex + 1]!;
      // Verificar se são dias consecutivos (nextDate deve ser posterior a date)
      final daysDiff = nextDate.difference(date).inDays;
      if (daysDiff == 1 && nextDate.isAfter(date)) {
        return _isDateSelected(nextDate);
      }
    }
    return false;
  }

  List<DateTime?> _getDaysForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    
    // Calcular o primeiro dia da semana do mês (0 = domingo, 6 = sábado)
    int firstDayOfWeek = getDayOfWeek(firstDay);
    // Converter Zeller (0=sábado, 1=domingo) para formato calendário (0=domingo, 6=sábado)
    int calendarFirstDay = (firstDayOfWeek == 1) ? 0 : (firstDayOfWeek == 0 ? 6 : firstDayOfWeek - 1);
    
    List<DateTime?> days = List.filled(42, null); // 6 semanas * 7 dias
    
    // Preencher dias vazios antes do primeiro dia do mês
    for (int i = 0; i < calendarFirstDay; i++) {
      days[i] = null;
    }
    
    // Preencher dias do mês
    for (int day = 1; day <= lastDay.day; day++) {
      days[calendarFirstDay + day - 1] = DateTime(month.year, month.month, day);
    }
    
    return days;
  }

  String _getMonthName(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[date.month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysForMonth(_currentMonth);
    const weekDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header com mês e ano
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  IconButton(
                    onPressed: _previousMonth,
                    icon: const Icon(Icons.chevron_left, color: AppTheme.black),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Text(
                    '${_getMonthName(_currentMonth)} ${_currentMonth.year}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.black,
                        ),
                  ),
                  IconButton(
                    onPressed: _nextMonth,
                    icon: const Icon(Icons.chevron_right, color: AppTheme.black),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Calendário
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Dias da semana
                  Row(
                    children: weekDays.map((day) {
                      return Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.darkGray,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Grid de dias
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 0.85, // Mais alto (menor valor = mais altura)
                    ),
                    itemCount: 42,
                    itemBuilder: (context, index) {
                      final date = days[index];
                      
                      if (date == null) {
                        return const SizedBox();
                      }
                      
                      final isStartOrEnd = _isDateStartOrEnd(date);
                      final isInMiddle = _isDateInMiddleRange(date);
                      final isSelected = isStartOrEnd || isInMiddle;
                      final isPreviousSelected = _isPreviousDaySelected(date, days, index);
                      final isNextSelected = _isNextDaySelected(date, days, index);
                      
                      // Calcular borderRadius para remover espaços entre selecionados
                      BorderRadius borderRadius;
                      if (isSelected) {
                        final leftRadius = isPreviousSelected ? 0.0 : 8.0;
                        final rightRadius = isNextSelected ? 0.0 : 8.0;
                        borderRadius = BorderRadius.horizontal(
                          left: Radius.circular(leftRadius),
                          right: Radius.circular(rightRadius),
                        );
                      } else {
                        borderRadius = BorderRadius.circular(8);
                      }
                      
                      return GestureDetector(
                        onTap: () => _onDayTap(date),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isStartOrEnd
                                ? AppTheme.darkGray
                                : isInMiddle
                                    ? const Color(0xFFE8E0D0) // Cor mais clara com mais branco
                                    : AppTheme.white,
                            borderRadius: borderRadius,
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Text(
                                  '${date.day}',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: isStartOrEnd
                                            ? AppTheme.white
                                            : AppTheme.black,
                                        fontWeight: isStartOrEnd
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                ),
                              ),
                              // Pontinho embaixo nos dias selecionados
                              if (isSelected)
                                Positioned(
                                  bottom: 6,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: isStartOrEnd
                                            ? AppTheme.white
                                            : AppTheme.darkGray,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (_selectedStartDate != null && _selectedEndDate != null)
                        ? () {
                            // Validar período: mínimo 14 dias, máximo 31 dias
                            final startOnly = DateTime(
                              _selectedStartDate!.year,
                              _selectedStartDate!.month,
                              _selectedStartDate!.day,
                            );
                            final endOnly = DateTime(
                              _selectedEndDate!.year,
                              _selectedEndDate!.month,
                              _selectedEndDate!.day,
                            );
                            final daysDiff = endOnly.difference(startOnly).inDays + 1;
                            
                            if (daysDiff < 14) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('O período deve ter no mínimo 14 dias'),
                                  backgroundColor: AppTheme.expenseRed,
                                ),
                              );
                              return;
                            }
                            
                            // Removida validação de máximo 31 dias - agora permite períodos maiores
                            // O calendário mostrará 31 dias de cada vez com scroll infinito
                            
                            Navigator.of(context).pop(<String, DateTime>{
                              'startDate': _selectedStartDate!,
                              'endDate': _selectedEndDate!,
                            });
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.black,
                      foregroundColor: AppTheme.white,
                      disabledBackgroundColor: AppTheme.darkGray.withOpacity(0.3),
                      disabledForegroundColor: AppTheme.darkGray,
                    ),
                    child: const Text('Confirmar'),
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
