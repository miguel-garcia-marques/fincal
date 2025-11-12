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
    console.log('Conectando ao MongoDB...');
    await connectDB();
    
    const Transaction = getTransactionModel();
    const Wallet = getWalletModel();
    const User = getUserModel();
    
    // 1. Encontrar todas as transações sem walletId ou com walletId inválido
    console.log('\n1. Buscando transações sem walletId ou com walletId inválido...');
    
    // Buscar transações onde walletId é null, undefined, ou não é um ObjectId válido
    const allTransactions = await Transaction.find({});
    console.log(`Total de transações encontradas: ${allTransactions.length}`);
    
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
    
    console.log(`Transações que precisam de migração: ${transactionsToMigrate.length}`);
    console.log(`Usuários únicos afetados: ${walletIdMap.size}`);
    
    if (transactionsToMigrate.length === 0) {
      console.log('\n✅ Nenhuma transação precisa de migração!');
      process.exit(0);
    }
    
    // 2. Para cada userId, encontrar ou criar wallet pessoal
    console.log('\n2. Encontrando ou criando wallets pessoais...');
    
    for (const [userId, _] of walletIdMap) {
      // Buscar wallet pessoal do usuário (onde ownerId = userId)
      let personalWallet = await Wallet.findOne({ ownerId: userId });
      
      if (!personalWallet) {
        // Criar wallet pessoal se não existir
        console.log(`  Criando wallet pessoal para usuário ${userId}...`);
        personalWallet = new Wallet({
          name: 'Minha Carteira Calendário',
          ownerId: userId,
        });
        await personalWallet.save();
        console.log(`  ✅ Wallet criada: ${personalWallet._id}`);
      } else {
        console.log(`  ✅ Wallet pessoal encontrada para usuário ${userId}: ${personalWallet._id}`);
      }
      
      walletIdMap.set(userId, personalWallet._id.toString());
    }
    
    // 3. Migrar transações
    console.log('\n3. Migrando transações...');
    let migratedCount = 0;
    let errorCount = 0;
    
    for (const tx of transactionsToMigrate) {
      try {
        const personalWalletId = walletIdMap.get(tx.userId);
        
        if (!personalWalletId) {
          console.error(`  ❌ Não foi possível encontrar wallet para userId: ${tx.userId}`);
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
          console.log(`  Migradas ${migratedCount} transações...`);
        }
      } catch (error) {
        console.error(`  ❌ Erro ao migrar transação ${tx._id}: ${error.message}`);
        errorCount++;
      }
    }
    
    console.log(`\n✅ Migração concluída!`);
    console.log(`   - Transações migradas: ${migratedCount}`);
    console.log(`   - Erros: ${errorCount}`);
    
    // 4. Verificação final
    console.log('\n4. Verificando resultado...');
    const remainingIssues = await Transaction.countDocuments({
      $or: [
        { walletId: { $exists: false } },
        { walletId: null },
        { walletId: { $type: 'string' } } // walletId deve ser ObjectId, não string
      ]
    });
    
    if (remainingIssues > 0) {
      console.log(`⚠️  Ainda há ${remainingIssues} transações com problemas.`);
    } else {
      console.log('✅ Todas as transações estão corretas!');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Erro durante migração:', error);
    process.exit(1);
  }
}

// Executar migração
migrateTransactions();

