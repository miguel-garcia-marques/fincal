const mongoose = require('mongoose');

const PasskeySchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true,
    index: true
  },
  credentialID: {
    type: String,
    required: true,
    unique: true
  },
  publicKey: {
    type: String,
    required: true
  },
  counter: {
    type: Number,
    default: 0
  },
  deviceType: {
    type: String,
    default: 'unknown'
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  lastUsedAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Função para obter o modelo
const getPasskeyModel = () => {
  const collectionName = 'passkeys';
  
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  return mongoose.model(collectionName, PasskeySchema, collectionName);
};

module.exports = { PasskeySchema, getPasskeyModel };

