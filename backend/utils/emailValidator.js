/**
 * Validador e sanitizador de emails para proteção contra XSS
 * Valida formato e remove caracteres perigosos
 */

/**
 * Valida formato básico de email
 * @param {string} email - Email a ser validado
 * @returns {boolean} - true se o formato é válido
 */
function isValidEmailFormat(email) {
  if (!email || typeof email !== 'string') {
    return false;
  }

  // Regex básico para validar formato de email
  // Cobre a maioria dos casos válidos sem ser muito restritivo
  const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  
  return emailRegex.test(email.trim());
}

/**
 * Remove caracteres perigosos que poderiam ser usados em ataques XSS
 * @param {string} input - String a ser sanitizada
 * @returns {string} - String sanitizada
 */
function removeDangerousCharacters(input) {
  if (!input || typeof input !== 'string') {
    return '';
  }

  // Lista de caracteres perigosos que não devem aparecer em emails válidos
  const dangerousChars = [
    '<', '>', '"', "'", '&', '\n', '\r', '\t',
    '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07',
    '\x08', '\x0B', '\x0C', '\x0E', '\x0F', '\x10', '\x11', '\x12',
    '\x13', '\x14', '\x15', '\x16', '\x17', '\x18', '\x19', '\x1A',
    '\x1B', '\x1C', '\x1D', '\x1E', '\x1F', '\x7F',
  ];

  let result = input;
  
  // Remover caracteres perigosos
  for (const char of dangerousChars) {
    result = result.replace(new RegExp(char.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), '');
  }

  // Remover sequências que poderiam ser interpretadas como scripts
  result = result.replace(/javascript:/gi, '');
  result = result.replace(/data:/gi, '');
  result = result.replace(/vbscript:/gi, '');
  result = result.replace(/on\w+\s*=/gi, ''); // Remove event handlers como onclick=, onerror=, etc.

  return result;
}

/**
 * Sanitiza um email removendo caracteres perigosos e validando formato
 * @param {string} email - Email a ser sanitizado
 * @returns {string|null} - Email sanitizado ou null se inválido
 */
function sanitizeEmail(email) {
  if (!email || typeof email !== 'string') {
    return null;
  }

  // Remover espaços no início e fim
  const trimmed = email.trim();

  // Validar formato básico de email
  if (!isValidEmailFormat(trimmed)) {
    return null;
  }

  // Remover caracteres perigosos
  const sanitized = removeDangerousCharacters(trimmed);

  // Validar novamente após sanitização
  if (!isValidEmailFormat(sanitized)) {
    return null;
  }

  // Limitar tamanho (RFC 5321: máximo 320 caracteres)
  if (sanitized.length > 320) {
    return null;
  }

  // Normalizar para lowercase
  return sanitized.toLowerCase();
}

/**
 * Valida se um email é seguro para processar
 * @param {string} email - Email a ser validado
 * @returns {boolean} - true se o email é seguro
 */
function isSafeEmail(email) {
  const sanitized = sanitizeEmail(email);
  return sanitized !== null && sanitized === email.toLowerCase().trim();
}

/**
 * Detecta padrões suspeitos que podem indicar tentativas de injeção
 * @param {string} email - Email a ser analisado
 * @returns {object} - Objeto com flags de suspeita
 */
function detectSuspiciousPatterns(email) {
  if (!email || typeof email !== 'string') {
    return { isSuspicious: true, reasons: ['Email vazio ou inválido'] };
  }

  const reasons = [];
  const lowerEmail = email.toLowerCase();

  // Padrões suspeitos
  if (email.includes('<script') || email.includes('</script>')) {
    reasons.push('Contém tags script');
  }
  if (email.includes('javascript:')) {
    reasons.push('Contém javascript:');
  }
  if (email.includes('onerror=') || email.includes('onclick=') || email.includes('onload=')) {
    reasons.push('Contém event handlers');
  }
  if (email.includes('data:text/html') || email.includes('data:image')) {
    reasons.push('Contém data URIs');
  }
  if (email.length > 320) {
    reasons.push('Email muito longo');
  }
  if (email.match(/[<>"']/)) {
    reasons.push('Contém caracteres HTML perigosos');
  }
  if (email.match(/[\x00-\x1F\x7F]/)) {
    reasons.push('Contém caracteres de controle');
  }
  if (email.split('@').length !== 2) {
    reasons.push('Formato de email inválido');
  }

  return {
    isSuspicious: reasons.length > 0,
    reasons: reasons.length > 0 ? reasons : []
  };
}

module.exports = {
  isValidEmailFormat,
  removeDangerousCharacters,
  sanitizeEmail,
  isSafeEmail,
  detectSuspiciousPatterns
};

