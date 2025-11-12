const mongoose = require('mongoose');
const crypto = require('crypto');

const InviteSchema = new mongoose.Schema({
  walletId: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Wallet',
    required: true, 
    index: true 
  },
  invitedBy: { 
    type: String, 
    required: true,
    index: true
  },
  email: { 
    type: String,
    index: true
  },
  token: { 
    type: String, 
    required: false, // Será gerado automaticamente no pre-save hook
    unique: true,
    index: true
  },
  permission: { 
    type: String, 
    required: true,
    enum: ['read', 'write'],
    default: 'read'
  },
  status: { 
    type: String, 
    required: true,
    enum: ['pending', 'accepted', 'expired'],
    default: 'pending'
  },
  expiresAt: { 
    type: Date, 
    required: true,
    default: () => new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // 30 dias
  },
  acceptedAt: { 
    type: Date 
  },
  acceptedBy: { 
    type: String 
  }
}, {
  timestamps: true
});

// Gerar token único antes de salvar (sempre gerar se não existir)
InviteSchema.pre('save', function(next) {
  if (!this.token || this.token.trim() === '') {
    this.token = crypto.randomBytes(32).toString('hex');
  }
  next();
});

// Validação customizada para garantir que o token existe após o pre-save
InviteSchema.pre('validate', function(next) {
  if (!this.token || this.token.trim() === '') {
    this.token = crypto.randomBytes(32).toString('hex');
  }
  next();
});

// Verificar se o convite expirou
InviteSchema.methods.isExpired = function() {
  return new Date() > this.expiresAt;
};

const getInviteModel = () => {
  const collectionName = 'invites';
  
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  return mongoose.model(collectionName, InviteSchema, collectionName);
};

module.exports = { InviteSchema, getInviteModel };

