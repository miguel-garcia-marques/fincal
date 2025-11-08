const mongoose = require('mongoose');

const SalaryAllocationSchema = new mongoose.Schema({
  gastosPercent: { type: Number, required: true },
  lazerPercent: { type: Number, required: true },
  poupancaPercent: { type: Number, required: true },
}, { _id: false });

const TransactionSchema = new mongoose.Schema({
  id: { type: String, required: true },
  userId: { type: String, required: true, index: true },
  type: { 
    type: String, 
    required: true, 
    enum: ['ganho', 'despesa'] 
  },
  date: { type: Date, required: true },
  description: { type: String },
  amount: { type: Number, required: true },
  category: { 
    type: String, 
    required: true,
    enum: [
      'compras', 'cafe', 'combustivel', 'subscricao', 'dizimo',
      'carro', 'multibanco', 'saude', 'comerFora', 'miscelaneos',
      'prendas', 'extras', 'snacks', 'comprasOnline', 'comprasRoupa', 'animais',
      // Categorias para ganhos
      'salario', 'alimentacao', 'outro'
    ]
  },
  isSalary: { type: Boolean, default: false },
  salaryAllocation: { type: SalaryAllocationSchema },
  expenseBudgetCategory: { 
    type: String,
    enum: ['gastos', 'lazer', 'poupanca']
  },
  frequency: { 
    type: String, 
    required: true,
    enum: ['unique', 'weekly', 'monthly'],
    default: 'unique'
  },
  dayOfWeek: { type: Number }, // 0=Sáb, 1=Dom, 2=Seg, etc.
  dayOfMonth: { type: Number }, // 1-31
}, {
  timestamps: true
});

// Índices para melhor performance
TransactionSchema.index({ userId: 1, date: 1 });
TransactionSchema.index({ userId: 1, type: 1 });
TransactionSchema.index({ userId: 1, frequency: 1 });
TransactionSchema.index({ userId: 1, id: 1 }, { unique: true });

// Função para obter o modelo dinâmico baseado no userId
const getTransactionModel = (userId) => {
  // Criar nome da collection baseado no userId
  const collectionName = `transactions_${userId.replace(/-/g, '_')}`;
  
  // Verificar se o modelo já existe
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  // Criar novo modelo com collection específica
  return mongoose.model(collectionName, TransactionSchema, collectionName);
};

module.exports = { TransactionSchema, getTransactionModel };

