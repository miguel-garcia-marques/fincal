const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const slowDown = require('express-slow-down');
const connectDB = require('./config/database');
const { securityMonitor, authSecurityMonitor } = require('./middleware/securityMonitor');
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
// SEGURANÇA: CORS Configurado (ANTES do rate limiting)
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

const isDevelopment = process.env.NODE_ENV !== 'production';

const corsOptions = {
  origin: function (origin, callback) {
    // Permitir requisições sem origin (ex: mobile apps, Postman em dev)
    if (!origin && isDevelopment) {
      return callback(null, true);
    }
    
    if (!origin) {
      return callback(null, true); // Permitir requisições sem origin em dev
    }
    
    // Em desenvolvimento, permitir qualquer porta do localhost ou 127.0.0.1
    if (isDevelopment) {
      if (origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:')) {
        return callback(null, true);
      }
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
      // Em desenvolvimento, ser mais permissivo
      if (isDevelopment) {
      callback(null, true);
    } else {
      callback(new Error('CORS: Origin não permitida'));
      }
    }
  },
  credentials: true,
  optionsSuccessStatus: 200,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
  exposedHeaders: ['Content-Range', 'X-Content-Range'],
  preflightContinue: false,
  maxAge: 86400 // 24 horas
};

// Aplicar CORS ANTES do rate limiting
app.use(cors(corsOptions));

// ============================================
// SEGURANÇA: Rate Limiting
// ============================================
// Rate limiter geral - mais permissivo em desenvolvimento
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: isDevelopment ? 1000 : 100, // muito mais permissivo em dev (1000 req/15min)
  message: 'Muitas requisições deste IP, tente novamente mais tarde.',
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => {
    // Pular rate limiting para preflight requests (OPTIONS)
    if (req.method === 'OPTIONS') {
      return true;
    }
    // Em desenvolvimento, pular rate limiting para localhost
    if (isDevelopment && (req.ip === '127.0.0.1' || req.ip === '::1' || req.ip === '::ffff:127.0.0.1')) {
      return true;
    }
    return false;
  },
});

// Rate limiter mais restritivo para endpoints de bulk/import
const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: isDevelopment ? 100 : 10, // mais permissivo em dev
  message: 'Muitas requisições de importação, tente novamente mais tarde.',
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => {
    // Pular rate limiting para preflight requests
    return req.method === 'OPTIONS';
  },
});

// Rate limiter específico para autenticação (login, signup, passkeys)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: isDevelopment ? 50 : 5, // Máximo 5 tentativas de login por 15 minutos em produção
  message: 'Muitas tentativas de login. Tente novamente em 15 minutos.',
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => {
    if (req.method === 'OPTIONS') {
      return true;
    }
    // Em desenvolvimento, pular rate limiting para localhost
    if (isDevelopment && (req.ip === '127.0.0.1' || req.ip === '::1' || req.ip === '::ffff:127.0.0.1')) {
      return true;
    }
    return false;
  },
  // Handler customizado para incluir informações de segurança
  handler: (req, res) => {
    const identifier = req.ip || req.headers['x-forwarded-for'] || 'unknown';
    console.warn(`[SECURITY] Rate limit excedido para autenticação:`, {
      identifier,
      path: req.path,
      method: req.method,
      timestamp: new Date().toISOString()
    });
    
    res.status(429).json({
      message: 'Muitas tentativas de login. Tente novamente em 15 minutos.',
      code: 'RATE_LIMIT_EXCEEDED',
      retryAfter: 900 // 15 minutos em segundos
    });
  }
});

// Slow down - desabilitado em desenvolvimento para melhor performance
const speedLimiter = slowDown({
  windowMs: 15 * 60 * 1000, // 15 minutos
  delayAfter: isDevelopment ? 500 : 50, // muito mais permissivo em dev
  delayMs: isDevelopment 
    ? () => 0  // Nova sintaxe para express-slow-down v2
    : (used, req) => {
        const delayAfter = req.slowDown?.limit || 50;
        return (used - delayAfter) * 500;
      },
  skip: (req) => {
    // Pular slow down para preflight requests
    if (req.method === 'OPTIONS') {
      return true;
    }
    // Em desenvolvimento, pular slow down para localhost
    if (isDevelopment && (req.ip === '127.0.0.1' || req.ip === '::1' || req.ip === '::ffff:127.0.0.1')) {
      return true;
    }
    return false;
  },
});

app.use(generalLimiter);
app.use(speedLimiter);

// ============================================
// SEGURANÇA: Monitoramento de segurança
// ============================================
// Aplicar monitoramento de segurança em todas as rotas
app.use(securityMonitor);

// ============================================
// SEGURANÇA: Limitar tamanho de payload
// ============================================
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ============================================
// SEGURANÇA: HTTPS Enforcement (em produção)
// ============================================
if (process.env.NODE_ENV === 'production') {
  app.use((req, res, next) => {
    // Verificar se a requisição já é HTTPS
    const isSecure = req.secure || 
                     req.headers['x-forwarded-proto'] === 'https' ||
                     req.headers['x-forwarded-ssl'] === 'on';
    
    if (!isSecure) {
      // Redirecionar para HTTPS
      return res.redirect(301, `https://${req.headers.host}${req.url}`);
    }
    
    // Adicionar header Strict-Transport-Security (HSTS)
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
    
    next();
  });
}

// ============================================
// Rotas
// ============================================
// Aplicar rate limiter mais restritivo para endpoints de bulk (antes das rotas)
app.use('/api/transactions/bulk', strictLimiter);

// Aplicar rate limiter específico para autenticação
app.use('/api/passkeys/authenticate', authLimiter);
app.use('/api/passkeys/authenticate/options', authLimiter);

app.use('/api/transactions', require('./routes/transactions'));
app.use('/api/users', require('./routes/users'));
app.use('/api/period-history', require('./routes/period_history'));
app.use('/api/wallets', require('./routes/wallets'));
app.use('/api/invites', require('./routes/invites'));
app.use('/api/passkeys', require('./routes/passkeys'));

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
  // Error handler
  
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
  // Server started
});
