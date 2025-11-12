/// Calcula o dia da semana usando a fórmula de Zeller
/// Retorna: 0 = sábado, 1 = domingo, 2 = segunda-feira, 3 = terça-feira,
/// 4 = quarta-feira, 5 = quinta-feira, 6 = sexta-feira
int getDayOfWeek(DateTime date) {
  int day = date.day;
  int month = date.month;
  int year = date.year;

  // Para janeiro e fevereiro, considerar como 13 e 14 do ano anterior
  if (month == 1 || month == 2) {
    month += 12;
    year -= 1;
  }

  // K é o ano do século (A mod 100)
  int K = year % 100;
  
  // J é o século (parte inteira de A/100)
  int J = year ~/ 100;

  // Fórmula de Zeller: h = (D + floor((13*(M + 1))/5) + K + floor(K/4) + floor(J/4) - 2*J) mod 7
  int h = (day + 
      (13 * (month + 1) ~/ 5) + 
      K + 
      (K ~/ 4) + 
      (J ~/ 4) - 
      2 * J) % 7;

  // Ajustar para garantir valor positivo
  if (h < 0) {
    h += 7;
  }

  return h;
}

String getDayName(int dayOfWeek) {
  switch (dayOfWeek) {
    case 0:
      return 'Sáb';
    case 1:
      return 'Dom';
    case 2:
      return 'Seg';
    case 3:
      return 'Ter';
    case 4:
      return 'Qua';
    case 5:
      return 'Qui';
    case 6:
      return 'Sex';
    default:
      return '';
  }
}

String getDayNameFull(int dayOfWeek) {
  switch (dayOfWeek) {
    case 0:
      return 'Sábado';
    case 1:
      return 'Domingo';
    case 2:
      return 'Segunda-feira';
    case 3:
      return 'Terça-feira';
    case 4:
      return 'Quarta-feira';
    case 5:
      return 'Quinta-feira';
    case 6:
      return 'Sexta-feira';
    default:
      return '';
  }
}
