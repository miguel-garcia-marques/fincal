const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const slowDown = require('express-slow-down');
const connectDB = require('./config/database');
require('dotenv').config();

const app = express();

// Conectar ao MongoDB
connectDB();

// ============================================
// SEGURANÇA: Headers de Segurança HTTP
// ============================================
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
  crossOriginEmbedderPolicy: false, // Permite requisições cross-origin se necessário
}));

// ============================================
// SEGURANÇA: Rate Limiting
// ============================================
// Rate limiter geral - 100 requisições por 15 minutos por IP
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: 100, // máximo 100 requisições por IP
  message: 'Muitas requisições deste IP, tente novamente mais tarde.',
  standardHeaders: true,
  legacyHeaders: false,
});

// Rate limiter mais restritivo para endpoints de bulk/import
const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: 10, // máximo 10 requisições por IP
  message: 'Muitas requisições de importação, tente novamente mais tarde.',
  standardHeaders: true,
  legacyHeaders: false,
});

// Slow down - adiciona delay progressivo após muitas requisições
const speedLimiter = slowDown({
  windowMs: 15 * 60 * 1000, // 15 minutos
  delayAfter: 50, // começa a adicionar delay após 50 requisições
  delayMs: 500, // adiciona 500ms de delay por requisição após o limite
});

app.use(generalLimiter);
app.use(speedLimiter);

// ============================================
// SEGURANÇA: CORS Configurado
// ============================================
    // Lista de origens permitidas
    const allowedOrigins = [
      'http://localhost:3000',
      'http://localhost:8080',
      'http://127.0.0.1:8080',
];

// Adicionar origens do Firebase se especificadas via env
if (process.env.ALLOWED_ORIGINS) {
  allowedOrigins.push(...process.env.ALLOWED_ORIGINS.split(','));
}

const corsOptions = {
  origin: function (origin, callback) {
    // Permitir requisições sem origin (ex: mobile apps, Postman em dev)
    if (!origin && process.env.NODE_ENV !== 'production') {
      return callback(null, true);
    }
    
    if (!origin) {
      return callback(new Error('CORS: Origin não permitida'));
    }
    
    // Em produção, aceitar origens do Firebase se configuradas
    if (process.env.NODE_ENV === 'production') {
      if (origin.includes('firebaseapp.com') || origin.includes('web.app') || origin.includes('firebasehosting.com')) {
        return callback(null, true);
      }
    }
    
    // Verificar se a origem está na lista permitida
    if (allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true);
    } else {
      callback(new Error('CORS: Origin não permitida'));
    }
  },
  credentials: true,
  optionsSuccessStatus: 200
};

app.use(cors(corsOptions));

// ============================================
// SEGURANÇA: Limitar tamanho de payload
// ============================================
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ============================================
// Rotas
// ============================================
// Aplicar rate limiter mais restritivo para endpoints de bulk (antes das rotas)
app.use('/api/transactions/bulk', strictLimiter);

app.use('/api/transactions', require('./routes/transactions'));
app.use('/api/users', require('./routes/users'));
app.use('/api/period-history', require('./routes/period_history'));

// Rota de teste
app.get('/', (req, res) => {
  res.json({ 
    message: 'FinCal API',
    version: '1.0.0',
    endpoints: {
      'GET /api/transactions': 'Obter todas as transações',
      'GET /api/transactions/range?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD': 'Obter transações em um período',
      'POST /api/transactions': 'Criar nova transação',
      'PUT /api/transactions/:id': 'Atualizar transação',
      'DELETE /api/transactions/:id': 'Deletar transação',
      'GET /api/users/me': 'Obter dados do usuário atual',
      'POST /api/users': 'Criar ou atualizar usuário',
      'PUT /api/users/me': 'Atualizar nome do usuário'
    }
  });
});

// ============================================
// SEGURANÇA: Tratamento de Erros
// ============================================
app.use((err, req, res, next) => {
  // Log completo apenas em desenvolvimento
  if (process.env.NODE_ENV !== 'production') {
    console.error('Erro completo:', err);
    console.error('Stack:', err.stack);
  } else {
    // Em produção, logar apenas informações essenciais
    console.error('Erro:', err.message);
    // Não logar stack trace em produção para não expor informações
  }
  
  // Resposta genérica para não expor detalhes do sistema
  const statusCode = err.statusCode || 500;
  const message = process.env.NODE_ENV === 'production' 
    ? 'Algo deu errado! Por favor, tente novamente mais tarde.' 
    : err.message || 'Algo deu errado!';
  
  res.status(statusCode).json({ 
    message,
    ...(process.env.NODE_ENV !== 'production' && { error: err.message })
  });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`API available at http://localhost:${PORT}/api/transactions`);
});

