const mongoose = require('mongoose');

const PeriodHistorySchema = new mongoose.Schema({
  id: { type: String, required: true },
  userId: { type: String, required: true, index: true },
  startDate: { type: Date, required: true },
  endDate: { type: Date, required: true },
  transactionIds: [{ type: String }], // IDs das transações presentes neste período
}, {
  timestamps: true
});

// Índices para melhor performance
PeriodHistorySchema.index({ userId: 1, startDate: -1 });
PeriodHistorySchema.index({ userId: 1, id: 1 }, { unique: true });

// Função para obter o modelo dinâmico baseado no userId
const getPeriodHistoryModel = (userId) => {
  // Criar nome da collection baseado no userId
  const collectionName = `period_history_${userId.replace(/-/g, '_')}`;
  
  // Verificar se o modelo já existe
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  // Criar novo modelo com collection específica
  return mongoose.model(collectionName, PeriodHistorySchema, collectionName);
};

module.exports = { PeriodHistorySchema, getPeriodHistoryModel };

