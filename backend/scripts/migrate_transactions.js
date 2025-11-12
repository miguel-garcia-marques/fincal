/**
 * Script de migração para associar transações antigas a wallets
 * 
 * Este script:
 * 1. Encontra transações sem walletId ou com walletId inválido
 * 2. Para cada usuário, encontra ou cria sua wallet pessoal
 * 3. Migra as transações antigas para a wallet pessoal do usuário
 */

require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/database');
const { getTransactionModel } = require('../models/Transaction');
const { getWalletModel } = require('../models/Wallet');
const { getUserModel } = require('../models/User');

async function migrateTransactions() {
  try {

    await connectDB();
    
    const Transaction = getTransactionModel();
    const Wallet = getWalletModel();
    const User = getUserModel();
    
    // 1. Encontrar todas as transações sem walletId ou com walletId inválido

    // Buscar transações onde walletId é null, undefined, ou não é um ObjectId válido
    const allTransactions = await Transaction.find({});

    const transactionsToMigrate = [];
    const walletIdMap = new Map(); // Mapear userId -> walletId pessoal
    
    for (const tx of allTransactions) {
      let needsMigration = false;
      
      // Verificar se walletId está ausente ou inválido
      if (!tx.walletId || !mongoose.Types.ObjectId.isValid(tx.walletId)) {
        needsMigration = true;
      } else {
        // Verificar se a wallet existe
        const wallet = await Wallet.findById(tx.walletId);
        if (!wallet) {
          needsMigration = true;
        }
      }
      
      if (needsMigration) {
        transactionsToMigrate.push(tx);
        
        // Adicionar userId ao mapa se ainda não estiver
        if (tx.userId && !walletIdMap.has(tx.userId)) {
          walletIdMap.set(tx.userId, null); // null significa que ainda não encontramos/criamos a wallet
        }
      }
    }

    if (transactionsToMigrate.length === 0) {

      process.exit(0);
    }
    
    // 2. Para cada userId, encontrar ou criar wallet pessoal

    for (const [userId, _] of walletIdMap) {
      // Buscar wallet pessoal do usuário (onde ownerId = userId)
      let personalWallet = await Wallet.findOne({ ownerId: userId });
      
      if (!personalWallet) {
        // Criar wallet pessoal se não existir

        personalWallet = new Wallet({
          name: 'Minha Carteira Calendário',
          ownerId: userId,
        });
        await personalWallet.save();

      } else {

      }
      
      walletIdMap.set(userId, personalWallet._id.toString());
    }
    
    // 3. Migrar transações

    let migratedCount = 0;
    let errorCount = 0;
    
    for (const tx of transactionsToMigrate) {
      try {
        const personalWalletId = walletIdMap.get(tx.userId);
        
        if (!personalWalletId) {

          errorCount++;
          continue;
        }
        
        // Atualizar transação com walletId correto
        await Transaction.updateOne(
          { _id: tx._id },
          { 
            $set: { 
              walletId: new mongoose.Types.ObjectId(personalWalletId),
              // Garantir que createdBy está definido
              createdBy: tx.createdBy || tx.userId
            } 
          }
        );
        
        migratedCount++;
        
        if (migratedCount % 100 === 0) {

        }
      } catch (error) {

        errorCount++;
      }
    }

    // 4. Verificação final

    const remainingIssues = await Transaction.countDocuments({
      $or: [
        { walletId: { $exists: false } },
        { walletId: null },
        { walletId: { $type: 'string' } } // walletId deve ser ObjectId, não string
      ]
    });
    
    if (remainingIssues > 0) {

    } else {

    }
    
    process.exit(0);
  } catch (error) {

    process.exit(1);
  }
}

// Executar migração
migrateTransactions();
