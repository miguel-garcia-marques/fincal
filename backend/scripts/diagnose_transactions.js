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
    console.log('Conectando ao MongoDB...');
    await connectDB();
    
    // Mostrar informações da conexão
    const db = mongoose.connection.db;
    const dbName = db.databaseName;
    console.log(`\n📊 Database conectado: ${dbName}`);
    console.log(`📊 Host: ${mongoose.connection.host}`);
    
    // Listar todas as collections disponíveis
    const collections = await db.listCollections().toArray();
    console.log(`\n📁 Collections disponíveis no banco "${dbName}":`);
    for (const coll of collections) {
      const count = await db.collection(coll.name).countDocuments();
      console.log(`   - ${coll.name}: ${count} documentos`);
    }
    
    const Transaction = getTransactionModel();
    const Wallet = getWalletModel();
    const User = getUserModel();
    
    console.log('\n=== DIAGNÓSTICO DE TRANSAÇÕES ===\n');
    
    // Verificar qual collection o modelo Transaction está usando
    const transactionCollectionName = Transaction.collection.name;
    console.log(`📋 Collection usada pelo modelo Transaction: "${transactionCollectionName}"`);
    
    // Verificar diretamente na collection
    const directCount = await db.collection(transactionCollectionName).countDocuments({});
    console.log(`📋 Documentos na collection "${transactionCollectionName}": ${directCount}`);
    
    // 1. Contar todas as transações usando o modelo
    const totalTransactions = await Transaction.countDocuments({});
    console.log(`1. Total de transações (via modelo): ${totalTransactions}`);
    
    // 2. Verificar transações sem walletId
    const transactionsWithoutWallet = await Transaction.countDocuments({
      $or: [
        { walletId: { $exists: false } },
        { walletId: null }
      ]
    });
    console.log(`2. Transações sem walletId: ${transactionsWithoutWallet}`);
    
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
    
    console.log(`3. Transações com walletId inválido (não é ObjectId): ${invalidWalletCount}`);
    console.log(`   Tipos de walletId encontrados:`, Object.fromEntries(walletIdTypes));
    
    // 4. Listar todas as wallets
    const wallets = await Wallet.find({});
    console.log(`\n4. Wallets no banco: ${wallets.length}`);
    for (const wallet of wallets) {
      const txCount = await Transaction.countDocuments({ walletId: wallet._id });
      console.log(`   - Wallet ID: ${wallet._id}, Owner: ${wallet.ownerId}, Nome: ${wallet.name}, Transações: ${txCount}`);
    }
    
    // 5. Listar todos os userIds únicos nas transações
    const uniqueUserIds = await Transaction.distinct('userId');
    console.log(`\n5. UserIds únicos nas transações: ${uniqueUserIds.length}`);
    for (const userId of uniqueUserIds.slice(0, 10)) { // Mostrar apenas os 10 primeiros
      const txCount = await Transaction.countDocuments({ userId });
      const txWithWallet = await Transaction.countDocuments({ 
        userId,
        walletId: { $exists: true, $ne: null }
      });
      console.log(`   - UserId: ${userId}, Total transações: ${txCount}, Com walletId: ${txWithWallet}`);
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
    
    console.log(`\n6. Transações com walletId que não existe (orphaned): ${orphanedCount}`);
    if (orphanedTransactions.length > 0) {
      console.log('   Exemplos:');
      orphanedTransactions.forEach(tx => {
        console.log(`     - TX ID: ${tx.txId}, walletId: ${tx.walletId}, userId: ${tx.userId}`);
      });
    }
    
    // 7. Verificar diretamente na collection (sem usar o modelo)
    console.log(`\n7. Verificando diretamente na collection "${transactionCollectionName}":`);
    const directTransactions = await db.collection(transactionCollectionName).find({}).limit(5).toArray();
    console.log(`   Documentos encontrados diretamente: ${directTransactions.length}`);
    for (const tx of directTransactions) {
      console.log(`   - _id: ${tx._id}, id: ${tx.id}, userId: ${tx.userId}, walletId: ${tx.walletId} (tipo: ${typeof tx.walletId}), tipo: ${tx.type}`);
    }
    
    // 8. Mostrar algumas transações de exemplo usando o modelo
    console.log(`\n8. Exemplos de transações via modelo (primeiras 5):`);
    const sampleTransactions = await Transaction.find({}).limit(5);
    console.log(`   Transações encontradas via modelo: ${sampleTransactions.length}`);
    for (const tx of sampleTransactions) {
      console.log(`   - ID: ${tx.id}, userId: ${tx.userId}, walletId: ${tx.walletId}, tipo: ${tx.type}, data: ${tx.date}, valor: ${tx.amount}`);
    }
    
    // 9. Verificar se há transações com walletId como string (usando query direta)
    const stringWalletIds = await db.collection(transactionCollectionName).find({
      walletId: { $type: 'string' }
    }).limit(5).toArray();
    
    if (stringWalletIds.length > 0) {
      console.log(`\n9. ⚠️  Encontradas transações com walletId como string (deveria ser ObjectId):`);
      for (const tx of stringWalletIds) {
        console.log(`   - TX _id: ${tx._id}, walletId (tipo: ${typeof tx.walletId}): ${tx.walletId}`);
      }
    } else {
      console.log(`\n9. ✅ Nenhuma transação com walletId como string encontrada`);
    }
    
    // 10. Verificar todas as collections que podem conter transações
    console.log(`\n10. Procurando por collections que podem conter transações:`);
    const possibleCollections = ['transactions', 'transaction', 'txs', 'transaction_models'];
    for (const collName of possibleCollections) {
      try {
        const exists = await db.listCollections({ name: collName }).hasNext();
        if (exists) {
          const count = await db.collection(collName).countDocuments({});
          console.log(`   - Collection "${collName}": ${count} documentos`);
          if (count > 0 && collName !== transactionCollectionName) {
            const sample = await db.collection(collName).findOne({});
            console.log(`     Exemplo: ${JSON.stringify(sample, null, 2).substring(0, 200)}...`);
          }
        }
      } catch (e) {
        // Collection não existe, ignorar
      }
    }
    
    console.log('\n=== FIM DO DIAGNÓSTICO ===\n');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Erro durante diagnóstico:', error);
    process.exit(1);
  }
}

// Executar diagnóstico
diagnoseTransactions();

