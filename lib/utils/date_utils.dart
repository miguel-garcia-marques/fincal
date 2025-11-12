import 'package:intl/intl.dart';

String formatDate(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}

String formatCurrency(double amount) {
  return '${amount.toStringAsFixed(2)} €';
}

List<DateTime> getDaysInRange(DateTime startDate, DateTime endDate) {
  List<DateTime> days = [];
  // Normalizar datas para UTC para evitar problemas de timezone
  DateTime current = DateTime.utc(startDate.year, startDate.month, startDate.day);
  DateTime end = DateTime.utc(endDate.year, endDate.month, endDate.day);
  
  // Incluir o último dia: continuar enquanto current <= end
  while (current.isBefore(end) || 
         (current.year == end.year && current.month == end.month && current.day == end.day)) {
    days.add(DateTime.utc(current.year, current.month, current.day));
    
    // Se chegamos ao último dia, parar
    if (current.year == end.year && current.month == end.month && current.day == end.day) {
      break;
    }
    
    current = current.add(const Duration(days: 1));
  }
  
  return days;
}

bool isSameDay(DateTime date1, DateTime date2) {
  return date1.year == date2.year &&
      date1.month == date2.month &&
      date1.day == date2.day;
}

String formatPeriod(DateTime startDate, DateTime endDate) {
  final startDay = startDate.day.toString().padLeft(2, '0');
  final startMonth = startDate.month.toString().padLeft(2, '0');
  final endDay = endDate.day.toString().padLeft(2, '0');
  final endMonth = endDate.month.toString().padLeft(2, '0');
  final year = startDate.year;
  
  return '$year | $startDay/$startMonth - $endDay/$endMonth';
}
