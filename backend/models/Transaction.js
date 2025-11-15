const mongoose = require('mongoose');

const SalaryAllocationSchema = new mongoose.Schema({
  gastosPercent: { type: Number, required: true },
  lazerPercent: { type: Number, required: true },
  poupancaPercent: { type: Number, required: true },
}, { _id: false });

const TransactionSchema = new mongoose.Schema({
  id: { type: String, required: true },
  userId: { type: String, required: true }, // Mantido para compatibilidade
  walletId: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Wallet',
    required: true
  },
  createdBy: { 
    type: String, 
    required: true
  },
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
      'comunicacoes',
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
  person: { type: String }, // Campo para pessoa (opcional, padrão "geral" quando não especificado)
  excludedDates: { 
    type: [Date], 
    default: [] 
  }, // Datas excluídas para transações periódicas (quando uma ocorrência específica foi editada)
}, {
  timestamps: true
});

// Índices para melhor performance
TransactionSchema.index({ userId: 1, date: 1 });
TransactionSchema.index({ userId: 1, type: 1 });
TransactionSchema.index({ userId: 1, frequency: 1 });
TransactionSchema.index({ userId: 1, id: 1 }, { unique: true });
TransactionSchema.index({ walletId: 1, date: 1 });
TransactionSchema.index({ walletId: 1, type: 1 });
TransactionSchema.index({ walletId: 1, id: 1 }, { unique: true });
TransactionSchema.index({ createdBy: 1 });

// Função para obter o modelo de transações
// Usamos uma collection por walletId para melhor performance e escalabilidade
const getTransactionModel = (walletId) => {
  if (!walletId) {
    throw new Error('walletId é obrigatório para obter o modelo de transações');
  }
  
  // Converter walletId para string se for ObjectId
  const walletIdStr = walletId.toString();
  
  // Nome da collection baseado no walletId
  const collectionName = `transactions_${walletIdStr}`;
  
  // Verificar se o modelo já existe
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  // Criar novo modelo com collection específica para este walletId
  return mongoose.model(collectionName, TransactionSchema, collectionName);
};

module.exports = { TransactionSchema, getTransactionModel };
