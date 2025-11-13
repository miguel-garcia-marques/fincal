const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
  userId: { 
    type: String, 
    required: true, 
    unique: true
  },
  email: { 
    type: String, 
    required: true
  },
  name: { 
    type: String, 
    required: true 
  },
  profilePictureUrl: {
    type: String,
    default: null
  },
  personalWalletId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Wallet',
    default: null
  },
  walletsInvited: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Wallet'
  }],
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

// Índices (removido duplicação - unique já cria índice automaticamente)
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
