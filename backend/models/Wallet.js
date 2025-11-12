const mongoose = require('mongoose');

const WalletSchema = new mongoose.Schema({
  name: { 
    type: String, 
    required: true,
    default: 'Minha Carteira Calendário'
  },
  ownerId: { 
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
WalletSchema.index({ ownerId: 1 });
WalletSchema.index({ createdAt: -1 });

const getWalletModel = () => {
  const collectionName = 'wallets';
  const modelName = 'Wallet'; // Nome usado no ref
  
  // Verificar se já existe com o nome do modelo
  if (mongoose.models[modelName]) {
    return mongoose.models[modelName];
  }
  
  // Verificar se existe com o nome da collection
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  // Registrar com o nome do modelo para funcionar com ref
  return mongoose.model(modelName, WalletSchema, collectionName);
};

// Validação pré-save para impedir múltiplas wallets pessoais
// IMPORTANTE: Esta validação deve ser definida DEPOIS de getWalletModel
WalletSchema.pre('save', async function(next) {
  // Apenas validar se for um novo documento (não update)
  if (this.isNew) {
    try {
      const Wallet = getWalletModel();
      // Verificar se já existe uma wallet com este ownerId
      const existingWallet = await Wallet.findOne({ ownerId: this.ownerId });
      if (existingWallet) {
        const error = new Error(`Usuário já possui uma wallet pessoal. Cada usuário pode ter apenas uma wallet pessoal.`);
        error.name = 'ValidationError';
        return next(error);
      }
    } catch (err) {
      // Se houver erro na validação, permitir salvar (não bloquear por erro de validação)
      console.warn('Aviso na validação de wallet única:', err.message);
    }
  }
  next();
});

module.exports = { WalletSchema, getWalletModel };

