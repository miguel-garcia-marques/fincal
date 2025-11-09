const express = require('express');
const cors = require('cors');
const connectDB = require('./config/database');
require('dotenv').config();

const app = express();

// Conectar ao MongoDB
connectDB();

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Rotas
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

// Tratamento de erros
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ message: 'Algo deu errado!' });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`API available at http://localhost:${PORT}/api/transactions`);
});

