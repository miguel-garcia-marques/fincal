const mongoose = require('mongoose');

const WalletMemberSchema = new mongoose.Schema({
  walletId: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Wallet',
    required: true
  },
  userId: { 
    type: String, 
    required: true
  },
  permission: { 
    type: String, 
    required: true,
    enum: ['read', 'write', 'owner'],
    default: 'read'
  },
  joinedAt: { 
    type: Date, 
    default: Date.now 
  }
}, {
  timestamps: true
});

// Índice composto para garantir que um usuário só pode ter uma relação por wallet
WalletMemberSchema.index({ walletId: 1, userId: 1 }, { unique: true });
WalletMemberSchema.index({ userId: 1 });
WalletMemberSchema.index({ walletId: 1 });

const getWalletMemberModel = () => {
  const collectionName = 'wallet_members';
  const modelName = 'WalletMember'; // Nome usado no ref (se necessário)
  
  // Verificar se já existe com o nome do modelo
  if (mongoose.models[modelName]) {
    return mongoose.models[modelName];
  }
  
  // Verificar se existe com o nome da collection
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  // Registrar com o nome do modelo
  return mongoose.model(modelName, WalletMemberSchema, collectionName);
};

module.exports = { WalletMemberSchema, getWalletMemberModel };

