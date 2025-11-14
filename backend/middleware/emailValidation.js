/**
 * Middleware de validação de email
 * Sanitiza e valida emails antes de processar
 */

const { sanitizeEmail, isSafeEmail, detectSuspiciousPatterns } = require('../utils/emailValidator');
const { logSuspiciousAttempt } = require('./securityMonitor');

/**
 * Valida e sanitiza email no body da requisição
 */
function validateEmailInBody(req, res, next) {
  if (req.body && req.body.email) {
    const email = req.body.email;
    
    // Detectar padrões suspeitos
    const suspicious = detectSuspiciousPatterns(email);
    if (suspicious.isSuspicious) {
      const identifier = req.ip || req.headers['x-forwarded-for'] || 'unknown';
      logSuspiciousAttempt(identifier, 'xss_email', {
        source: 'body',
        email: email.substring(0, 100),
        reasons: suspicious.reasons
      });
      
      return res.status(400).json({
        message: 'Formato de email inválido ou contém caracteres não permitidos',
        code: 'INVALID_EMAIL'
      });
    }
    
    // Sanitizar email
    const sanitized = sanitizeEmail(email);
    if (sanitized === null) {
      return res.status(400).json({
        message: 'Formato de email inválido',
        code: 'INVALID_EMAIL'
      });
    }
    
    // Substituir email no body pelo sanitizado
    req.body.email = sanitized;
  }
  
  next();
}

/**
 * Valida e sanitiza email em query params
 */
function validateEmailInQuery(req, res, next) {
  if (req.query && req.query.email) {
    const email = req.query.email;
    
    const suspicious = detectSuspiciousPatterns(email);
    if (suspicious.isSuspicious) {
      const identifier = req.ip || req.headers['x-forwarded-for'] || 'unknown';
      logSuspiciousAttempt(identifier, 'xss_email', {
        source: 'query',
        email: email.substring(0, 100),
        reasons: suspicious.reasons
      });
      
      return res.status(400).json({
        message: 'Formato de email inválido ou contém caracteres não permitidos',
        code: 'INVALID_EMAIL'
      });
    }
    
    const sanitized = sanitizeEmail(email);
    if (sanitized === null) {
      return res.status(400).json({
        message: 'Formato de email inválido',
        code: 'INVALID_EMAIL'
      });
    }
    
    req.query.email = sanitized;
  }
  
  next();
}

module.exports = {
  validateEmailInBody,
  validateEmailInQuery
};

