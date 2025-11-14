/**
 * Middleware de monitoramento de segurança
 * Detecta e registra tentativas suspeitas de ataque
 */

const { detectSuspiciousPatterns, sanitizeEmail } = require('../utils/emailValidator');

// Armazenamento em memória de tentativas suspeitas (em produção, usar Redis)
const suspiciousAttempts = new Map();
const MAX_SUSPICIOUS_ATTEMPTS = 5;
const SUSPICIOUS_WINDOW_MS = 15 * 60 * 1000; // 15 minutos

/**
 * Limpa tentativas antigas do cache
 */
function cleanOldAttempts() {
  const now = Date.now();
  for (const [key, data] of suspiciousAttempts.entries()) {
    if (now - data.firstAttempt > SUSPICIOUS_WINDOW_MS) {
      suspiciousAttempts.delete(key);
    }
  }
}

/**
 * Registra tentativa suspeita
 * @param {string} identifier - IP ou identificador do usuário
 * @param {string} type - Tipo de tentativa (xss, sql_injection, etc.)
 * @param {object} details - Detalhes da tentativa
 */
function logSuspiciousAttempt(identifier, type, details) {
  // Limpar tentativas antigas periodicamente
  if (Math.random() < 0.1) { // 10% de chance a cada requisição
    cleanOldAttempts();
  }

  const key = `${identifier}:${type}`;
  const now = Date.now();
  
  if (!suspiciousAttempts.has(key)) {
    suspiciousAttempts.set(key, {
      count: 1,
      firstAttempt: now,
      lastAttempt: now,
      details: [details]
    });
  } else {
    const existing = suspiciousAttempts.get(key);
    existing.count++;
    existing.lastAttempt = now;
    existing.details.push(details);
    
    // Manter apenas os últimos 10 detalhes
    if (existing.details.length > 10) {
      existing.details.shift();
    }
  }

  const attempt = suspiciousAttempts.get(key);
  
  // Log da tentativa suspeita
  console.warn(`[SECURITY] Tentativa suspeita detectada:`, {
    identifier,
    type,
    count: attempt.count,
    details: details,
    timestamp: new Date().toISOString()
  });

  // Se exceder o limite, logar como alerta crítico
  if (attempt.count >= MAX_SUSPICIOUS_ATTEMPTS) {
    console.error(`[SECURITY ALERT] Múltiplas tentativas suspeitas detectadas:`, {
      identifier,
      type,
      count: attempt.count,
      window: `${SUSPICIOUS_WINDOW_MS / 1000}s`,
      details: attempt.details
    });
  }

  return attempt.count;
}

/**
 * Verifica se um identificador excedeu o limite de tentativas suspeitas
 * @param {string} identifier - IP ou identificador do usuário
 * @param {string} type - Tipo de tentativa
 * @returns {boolean} - true se excedeu o limite
 */
function hasExceededLimit(identifier, type) {
  const key = `${identifier}:${type}`;
  const attempt = suspiciousAttempts.get(key);
  
  if (!attempt) {
    return false;
  }

  const now = Date.now();
  
  // Se passou a janela de tempo, resetar
  if (now - attempt.firstAttempt > SUSPICIOUS_WINDOW_MS) {
    suspiciousAttempts.delete(key);
    return false;
  }

  return attempt.count >= MAX_SUSPICIOUS_ATTEMPTS;
}

/**
 * Middleware para monitorar requisições suspeitas
 */
function securityMonitor(req, res, next) {
  const identifier = req.ip || req.headers['x-forwarded-for'] || 'unknown';
  
  // Verificar emails em body e query params
  const checkEmail = (email, source) => {
    if (!email || typeof email !== 'string') {
      return;
    }

    const suspicious = detectSuspiciousPatterns(email);
    
    if (suspicious.isSuspicious) {
      const count = logSuspiciousAttempt(identifier, 'xss_email', {
        source,
        email: email.substring(0, 100), // Limitar tamanho do log
        reasons: suspicious.reasons
      });

      // Se exceder limite, bloquear requisição
      if (hasExceededLimit(identifier, 'xss_email')) {
        return res.status(400).json({
          message: 'Múltiplas tentativas suspeitas detectadas. Acesso temporariamente bloqueado.',
          code: 'SECURITY_BLOCK'
        });
      }
    }
  };

  // Verificar email no body
  if (req.body && req.body.email) {
    checkEmail(req.body.email, 'body');
    
    // Sanitizar email no body
    const sanitized = sanitizeEmail(req.body.email);
    if (sanitized === null && req.body.email) {
      // Email inválido após sanitização
      logSuspiciousAttempt(identifier, 'invalid_email', {
        source: 'body',
        email: req.body.email.substring(0, 100)
      });
      
      return res.status(400).json({
        message: 'Formato de email inválido',
        code: 'INVALID_EMAIL'
      });
    }
    
    // Substituir email no body pelo sanitizado
    if (sanitized) {
      req.body.email = sanitized;
    }
  }

  // Verificar email em query params
  if (req.query && req.query.email) {
    checkEmail(req.query.email, 'query');
    
    const sanitized = sanitizeEmail(req.query.email);
    if (sanitized === null && req.query.email) {
      return res.status(400).json({
        message: 'Formato de email inválido',
        code: 'INVALID_EMAIL'
      });
    }
    
    if (sanitized) {
      req.query.email = sanitized;
    }
  }

  next();
}

/**
 * Middleware específico para rotas de autenticação
 */
function authSecurityMonitor(req, res, next) {
  const identifier = req.ip || req.headers['x-forwarded-for'] || 'unknown';
  
  // Verificar se já excedeu limite de tentativas suspeitas
  if (hasExceededLimit(identifier, 'xss_email') || 
      hasExceededLimit(identifier, 'invalid_email')) {
    return res.status(429).json({
      message: 'Muitas tentativas suspeitas. Tente novamente mais tarde.',
      code: 'SECURITY_BLOCK',
      retryAfter: Math.ceil(SUSPICIOUS_WINDOW_MS / 1000)
    });
  }

  // Aplicar monitoramento geral
  securityMonitor(req, res, next);
}

module.exports = {
  securityMonitor,
  authSecurityMonitor,
  logSuspiciousAttempt,
  hasExceededLimit
};

