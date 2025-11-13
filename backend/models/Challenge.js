const mongoose = require('mongoose');

const ChallengeSchema = new mongoose.Schema({
  challenge: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  challengeBuffer: {
    type: String, // Armazenar como base64 para preservar bytes exatos
    required: true
  },
  userId: {
    type: String,
    required: true,
    index: true
  },
  type: {
    type: String,
    enum: ['registration', 'authentication'],
    required: true
  },
  createdAt: {
    type: Date,
    default: Date.now,
    expires: 300 // Expira em 5 minutos (300 segundos) - TTL automático do MongoDB
  }
}, {
  timestamps: false // Não precisamos de updatedAt
});

// Índice TTL para expiração automática
ChallengeSchema.index({ createdAt: 1 }, { expireAfterSeconds: 300 });

// Função para obter o modelo
const getChallengeModel = () => {
  const collectionName = 'challenges';
  
  if (mongoose.models[collectionName]) {
    return mongoose.models[collectionName];
  }
  
  return mongoose.model(collectionName, ChallengeSchema, collectionName);
};

module.exports = { ChallengeSchema, getChallengeModel };

