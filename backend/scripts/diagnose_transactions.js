/**
 * Script de diagnóstico para verificar transações no MongoDB
 * 
 * Este script ajuda a identificar por que as transações não aparecem na app
 */

require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/database');
const { getTransactionModel } = require('../models/Transaction');
const { getWalletModel } = require('../models/Wallet');
const { getUserModel } = require('../models/User');

async function diagnoseTransactions() {
  try {

    await connectDB();
    
    // Mostrar informações da conexão
    const db = mongoose.connection.db;
    const dbName = db.databaseName;

    // Listar todas as collections disponíveis
    const collections = await db.listCollections().toArray();

    for (const coll of collections) {
      const count = await db.collection(coll.name).countDocuments();

    }
    
    const Transaction = getTransactionModel();
    const Wallet = getWalletModel();
    const User = getUserModel();

    // Verificar qual collection o modelo Transaction está usando
    const transactionCollectionName = Transaction.collection.name;

    // Verificar diretamente na collection
    const directCount = await db.collection(transactionCollectionName).countDocuments({});

    // 1. Contar todas as transações usando o modelo
    const totalTransactions = await Transaction.countDocuments({});
    
    // 2. Verificar transações sem walletId
    const transactionsWithoutWallet = await Transaction.countDocuments({
      $or: [
        { walletId: { $exists: false } },
        { walletId: null }
      ]
    });

    // 3. Verificar transações com walletId inválido (string em vez de ObjectId)
    const transactionsWithInvalidWallet = await Transaction.find({
      walletId: { $exists: true, $ne: null }
    });
    
    let invalidWalletCount = 0;
    const walletIdTypes = new Map();
    
    for (const tx of transactionsWithInvalidWallet) {
      const walletIdValue = tx.walletId;
      const type = typeof walletIdValue;
      walletIdTypes.set(type, (walletIdTypes.get(type) || 0) + 1);
      
      if (!mongoose.Types.ObjectId.isValid(walletIdValue)) {
        invalidWalletCount++;
      }
    }
    
    
    // 4. Listar todas as wallets
    const wallets = await Wallet.find({});

    for (const wallet of wallets) {
      const txCount = await Transaction.countDocuments({ walletId: wallet._id });

    }
    
    // 5. Listar todos os userIds únicos nas transações
    const uniqueUserIds = await Transaction.distinct('userId');

    for (const userId of uniqueUserIds.slice(0, 10)) { // Mostrar apenas os 10 primeiros
      const txCount = await Transaction.countDocuments({ userId });
      const txWithWallet = await Transaction.countDocuments({ 
        userId,
        walletId: { $exists: true, $ne: null }
      });

    }
    
    // 6. Verificar transações com walletId que não existe
    let orphanedCount = 0;
    const orphanedTransactions = [];
    
    for (const tx of transactionsWithInvalidWallet.slice(0, 100)) { // Verificar apenas as primeiras 100
      if (mongoose.Types.ObjectId.isValid(tx.walletId)) {
        const wallet = await Wallet.findById(tx.walletId);
        if (!wallet) {
          orphanedCount++;
          if (orphanedTransactions.length < 5) {
            orphanedTransactions.push({
              txId: tx._id,
              walletId: tx.walletId,
              userId: tx.userId
            });
          }
        }
      }
    }
    
    if (orphanedTransactions.length > 0) {

      orphanedTransactions.forEach(tx => {

      });
    }
    
    // 7. Verificar diretamente na collection (sem usar o modelo)

    const directTransactions = await db.collection(transactionCollectionName).find({}).limit(5).toArray();

    for (const tx of directTransactions) {
    }
    
    // 8. Mostrar algumas transações de exemplo usando o modelo
    const sampleTransactions = await Transaction.find({}).limit(5);

    for (const tx of sampleTransactions) {

    }
    
    // 9. Verificar se há transações com walletId como string (usando query direta)
    const stringWalletIds = await db.collection(transactionCollectionName).find({
      walletId: { $type: 'string' }
    }).limit(5).toArray();
    
    if (stringWalletIds.length > 0) {
      for (const tx of stringWalletIds) {
      }
    } else {

    }
    
    // 10. Verificar todas as collections que podem conter transações

    const possibleCollections = ['transactions', 'transaction', 'txs', 'transaction_models'];
    for (const collName of possibleCollections) {
      try {
        const exists = await db.listCollections({ name: collName }).hasNext();
        if (exists) {
          const count = await db.collection(collName).countDocuments({});

          if (count > 0 && collName !== transactionCollectionName) {
            const sample = await db.collection(collName).findOne({});
          }
        }
      } catch (e) {
        // Collection não existe, ignorar
      }
    }

    process.exit(0);
  } catch (error) {

    process.exit(1);
  }
}

// Executar diagnóstico
diagnoseTransactions();
