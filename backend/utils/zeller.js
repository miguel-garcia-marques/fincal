/**
 * Calcula o dia da semana usando a fórmula de Zeller
 * Retorna: 0 = sábado, 1 = domingo, 2 = segunda-feira, etc.
 */
function getDayOfWeek(day, month, year) {
  // Para janeiro e fevereiro, considerar como 13 e 14 do ano anterior
  if (month === 1 || month === 2) {
    month += 12;
    year -= 1;
  }

  // K é o ano do século (A mod 100)
  const K = year % 100;
  
  // J é o século (parte inteira de A/100)
  const J = Math.floor(year / 100);

  // Fórmula de Zeller
  let h = (day + 
      Math.floor((13 * (month + 1)) / 5) + 
      K + 
      Math.floor(K / 4) + 
      Math.floor(J / 4) - 
      2 * J) % 7;

  // Ajustar para garantir valor positivo
  if (h < 0) {
    h += 7;
  }

  return h;
}

module.exports = { getDayOfWeek };

