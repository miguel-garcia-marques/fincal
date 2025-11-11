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
    .isFloat({ min: 0.01 }).withMessage('Valor deve ser um número positivo maior que zero'),
  
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
      const dateRegex = /^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(\.\d{3})?(Z|[+-]\d{2}:\d{2})?)?$/;
      if (typeof value === 'string' && (dateRegex.test(value) || /^\d{4}-\d{2}-\d{2}$/.test(value))) {
        const date = new Date(value);
        if (isNaN(date.getTime())) {
          throw new Error('Data inválida');
        }
        return true;
      }
      throw new Error('Data deve estar no formato YYYY-MM-DD ou ISO8601');
    }),
  
  body('frequency')
    .optional()
    .isIn(['unique', 'weekly', 'monthly']).withMessage('Frequência deve ser "unique", "weekly" ou "monthly"'),
  
  body('dayOfWeek')
    .optional()
    .isInt({ min: 0, max: 6 }).withMessage('Dia da semana deve ser entre 0 e 6'),
  
  body('dayOfMonth')
    .optional()
    .isInt({ min: 1, max: 31 }).withMessage('Dia do mês deve ser entre 1 e 31'),
  
  body('description')
    .optional()
    .isLength({ max: 500 }).withMessage('Descrição deve ter no máximo 500 caracteres'),
  
  body('expenseBudgetCategory')
    .optional()
    .isIn(['gastos', 'lazer', 'poupanca']).withMessage('Categoria de orçamento inválida'),
  
  body('salaryAllocation.gastosPercent')
    .optional()
    .isFloat({ min: 0, max: 100 }).withMessage('Percentual de gastos deve ser entre 0 e 100'),
  
  body('salaryAllocation.lazerPercent')
    .optional()
    .isFloat({ min: 0, max: 100 }).withMessage('Percentual de lazer deve ser entre 0 e 100'),
  
  body('salaryAllocation.poupancaPercent')
    .optional()
    .isFloat({ min: 0, max: 100 }).withMessage('Percentual de poupança deve ser entre 0 e 100'),
  
  body('person')
    .optional()
    .isLength({ max: 100 }).withMessage('Nome da pessoa deve ter no máximo 100 caracteres'),
  
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

// Validação para usuário
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
  validatePeriodHistory,
  validatePeriodId,
  handleValidationErrors
};

