const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
  userId: { 
    type: String, 
    required: true, 
    unique: true,
    index: true 
  },
  email: { 
    type: String, 
    required: true,
    index: true 
  },
  name: { 
    type: String, 
    required: true 
  },
  createdAt: { 
    type: Date, 
    default: Date.now 
  },
  updatedAt: { 
    type: Date, 
    default: Date.now 
  }
}, {
  timestamps: true
});

// Índices
UserSchema.index({ userId: 1 }, { unique: true });
UserSchema.index({ email: 1 });

// Função para obter o modelo dinâmico baseado no userId (usando collection única)
const getUserModel = () => {
  // Usar uma collection única para todos os usuários
  const collectionName = 'users';
  
  // Verificar se o modelo já existe
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  // Criar novo modelo
  return mongoose.model(collectionName, UserSchema, collectionName);
};

module.exports = { UserSchema, getUserModel };

