const { body, query, param, validationResult } = require('express-validator');

// Middleware para processar resultados da validação
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      message: 'Dados de entrada inválidos',
      errors: errors.array()
    });
  }
  next();
};

// Validações para transações
const validateTransaction = [
  body('type')
    .notEmpty().withMessage('Tipo é obrigatório')
    .isIn(['ganho', 'despesa']).withMessage('Tipo deve ser "ganho" ou "despesa"'),
  
  body('amount')
    .notEmpty().withMessage('Valor é obrigatório')
    .custom((value) => {
      // Aceitar tanto número quanto string
      const numValue = typeof value === 'string' ? parseFloat(value) : value;
      if (isNaN(numValue) || numValue <= 0) {
        throw new Error('Valor deve ser um número positivo maior que zero');
      }
      return true;
    }),
  
  body('category')
    .notEmpty().withMessage('Categoria é obrigatória')
    .isIn([
      'compras', 'cafe', 'combustivel', 'subscricao', 'dizimo',
      'carro', 'multibanco', 'saude', 'comerFora', 'miscelaneos',
      'prendas', 'extras', 'snacks', 'comprasOnline', 'comprasRoupa', 'animais',
      'comunicacoes', 'salario', 'alimentacao', 'outro'
    ]).withMessage('Categoria inválida'),
  
  body('date')
    .notEmpty().withMessage('Data é obrigatória')
    .custom((value) => {
      // Aceitar formato YYYY-MM-DD ou ISO8601
      if (typeof value === 'string') {
        // Verificar formato YYYY-MM-DD simples primeiro
        if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
          const date = new Date(value);
          if (!isNaN(date.getTime())) {
            return true;
          }
        }
        // Verificar formato ISO8601 completo
        const isoRegex = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?(Z|[+-]\d{2}:\d{2})?$/;
        if (isoRegex.test(value)) {
          const date = new Date(value);
          if (!isNaN(date.getTime())) {
            return true;
          }
        }
      }
      throw new Error('Data deve estar no formato YYYY-MM-DD ou ISO8601');
    }),
  
  body('frequency')
    .optional({ nullable: true })
    .custom((value) => {
      if (value === null || value === undefined) return true;
      if (!['unique', 'weekly', 'monthly'].includes(value)) {
        throw new Error('Frequência deve ser "unique", "weekly" ou "monthly"');
      }
      return true;
    }),
  
  body('dayOfWeek')
    .optional({ nullable: true })
    .custom((value) => {
      if (value === null || value === undefined) return true;
      const intValue = parseInt(value);
      if (isNaN(intValue) || intValue < 0 || intValue > 6) {
        throw new Error('Dia da semana deve ser entre 0 e 6');
      }
      return true;
    }),
  
  body('dayOfMonth')
    .optional({ nullable: true })
    .custom((value) => {
      if (value === null || value === undefined) return true;
      const intValue = parseInt(value);
      if (isNaN(intValue) || intValue < 1 || intValue > 31) {
        throw new Error('Dia do mês deve ser entre 1 e 31');
      }
      return true;
    }),
  
  body('description')
    .optional({ nullable: true })
    .custom((value) => {
      if (value === null || value === undefined) return true;
      if (typeof value === 'string' && value.length > 500) {
        throw new Error('Descrição deve ter no máximo 500 caracteres');
      }
      return true;
    }),
  
  body('expenseBudgetCategory')
    .optional({ nullable: true })
    .custom((value) => {
      if (value === null || value === undefined) return true;
      if (!['gastos', 'lazer', 'poupanca'].includes(value)) {
        throw new Error('Categoria de orçamento inválida');
      }
      return true;
    }),
  
  body('salaryAllocation')
    .optional({ nullable: true })
    .custom((value, { req }) => {
      // Se salaryAllocation for null ou undefined, está OK
      if (value === null || value === undefined) return true;
      
      // Se for um objeto, validar os campos
      if (typeof value === 'object') {
        const gastos = parseFloat(value.gastosPercent);
        const lazer = parseFloat(value.lazerPercent);
        const poupanca = parseFloat(value.poupancaPercent);
        
        if (isNaN(gastos) || gastos < 0 || gastos > 100) {
          throw new Error('Percentual de gastos deve ser entre 0 e 100');
        }
        if (isNaN(lazer) || lazer < 0 || lazer > 100) {
          throw new Error('Percentual de lazer deve ser entre 0 e 100');
        }
        if (isNaN(poupanca) || poupanca < 0 || poupanca > 100) {
          throw new Error('Percentual de poupança deve ser entre 0 e 100');
        }
      }
      
      return true;
    }),
  
  body('person')
    .optional({ nullable: true })
    .custom((value) => {
      if (value === null || value === undefined) return true;
      if (typeof value === 'string' && value.length > 100) {
        throw new Error('Nome da pessoa deve ter no máximo 100 caracteres');
      }
      return true;
    }),
  
  handleValidationErrors
];

// Validação para query de range de transações
const validateTransactionRange = [
  query('startDate')
    .notEmpty().withMessage('startDate é obrigatório')
    .matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('startDate deve estar no formato YYYY-MM-DD'),
  
  query('endDate')
    .notEmpty().withMessage('endDate é obrigatório')
    .matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('endDate deve estar no formato YYYY-MM-DD'),
  
  handleValidationErrors
];

// Validação para ID de transação
const validateTransactionId = [
  param('id')
    .notEmpty().withMessage('ID é obrigatório')
    .isLength({ min: 1, max: 200 }).withMessage('ID inválido'),
  
  handleValidationErrors
];

// Validação para bulk import
const validateBulkTransactions = [
  body('transactions')
    .notEmpty().withMessage('transactions é obrigatório')
    .isArray().withMessage('transactions deve ser um array')
    .custom((value) => {
      if (value.length > 1000) {
        throw new Error('Máximo de 1000 transações por importação');
      }
      return true;
    }),
  
  handleValidationErrors
];

// Validação para usuário (criação)
const validateUser = [
  body('name')
    .notEmpty().withMessage('Nome é obrigatório')
    .trim()
    .isLength({ min: 1, max: 100 }).withMessage('Nome deve ter entre 1 e 100 caracteres')
    .custom((value) => {
      // Permitir letras, números, espaços e alguns caracteres especiais comuns
      if (!/^[\p{L}\p{N}\s.'-]+$/u.test(value)) {
        throw new Error('Nome contém caracteres inválidos');
      }
      return true;
    }),
  
  handleValidationErrors
];

// Validação para atualização de perfil (permite atualizar apenas name, apenas profilePictureUrl, ou ambos)
const validateUserUpdate = [
  body('name')
    .optional({ nullable: true })
    .trim()
    .isLength({ min: 1, max: 100 }).withMessage('Nome deve ter entre 1 e 100 caracteres')
    .custom((value) => {
      if (value === null || value === undefined || value === '') {
        return true; // Permitir null/undefined/vazio quando opcional
      }
      // Permitir letras, números, espaços e alguns caracteres especiais comuns
      if (!/^[\p{L}\p{N}\s.'-]+$/u.test(value)) {
        throw new Error('Nome contém caracteres inválidos');
      }
      return true;
    }),
  
  body('profilePictureUrl')
    .optional({ nullable: true, checkFalsy: true })
    .custom((value) => {
      // Permitir null, undefined ou string vazia
      if (value === null || value === undefined || value === '') {
        return true;
      }
      // Se for uma string, validar formato e tamanho
      if (typeof value !== 'string') {
        console.error('[VALIDATION] profilePictureUrl não é uma string:', typeof value, value);
        throw new Error('profilePictureUrl deve ser uma string');
      }
      if (value.length > 500) {
        console.error('[VALIDATION] profilePictureUrl muito longo:', value.length);
        throw new Error('URL da foto de perfil deve ter no máximo 500 caracteres');
      }
      // Validar formato de URL básico
      try {
        new URL(value);
        console.log('[VALIDATION] profilePictureUrl válido:', value);
        return true;
      } catch (urlError) {
        console.error('[VALIDATION] profilePictureUrl inválido:', value, urlError);
        throw new Error('profilePictureUrl deve ser uma URL válida');
      }
    }),
  
  // Garantir que pelo menos um campo seja fornecido
  body().custom((value, { req }) => {
    const hasName = value.name !== undefined && value.name !== null && value.name !== '';
    const hasProfilePictureUrl = value.profilePictureUrl !== undefined;
    
    if (!hasName && !hasProfilePictureUrl) {
      throw new Error('Pelo menos um campo (name ou profilePictureUrl) deve ser fornecido');
    }
    return true;
  }),
  
  handleValidationErrors
];

// Validação para período histórico
const validatePeriodHistory = [
  body('startDate')
    .notEmpty().withMessage('startDate é obrigatório')
    .matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('startDate deve estar no formato YYYY-MM-DD'),
  
  body('endDate')
    .notEmpty().withMessage('endDate é obrigatório')
    .matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('endDate deve estar no formato YYYY-MM-DD'),
  
  body('name')
    .optional()
    .isLength({ max: 200 }).withMessage('Nome deve ter no máximo 200 caracteres'),
  
  body('transactionIds')
    .optional()
    .isArray().withMessage('transactionIds deve ser um array'),
  
  handleValidationErrors
];

// Validação para ID de período
const validatePeriodId = [
  param('id')
    .notEmpty().withMessage('ID é obrigatório')
    .isLength({ min: 1, max: 200 }).withMessage('ID inválido'),
  
  handleValidationErrors
];

module.exports = {
  validateTransaction,
  validateTransactionRange,
  validateTransactionId,
  validateBulkTransactions,
  validateUser,
  validateUserUpdate,
  validatePeriodHistory,
  validatePeriodId,
  handleValidationErrors
};
