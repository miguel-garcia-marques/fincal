/**
 * Script para consolidar wallets duplicadas de usuários
 * 
 * Este script:
 * 1. Encontra usuários com múltiplas wallets pessoais
 * 2. Escolhe uma wallet principal (a mais antiga ou a que está no personalWalletId)
 * 3. Move todas as transações das wallets duplicadas para a wallet principal
 * 4. Deleta as wallets duplicadas
 * 5. Atualiza o personalWalletId do usuário
 * 
 * Uso: node backend/scripts/consolidate_duplicate_wallets.js
 */

require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/database');
const { getWalletModel } = require('../models/Wallet');
const { getWalletMemberModel } = require('../models/WalletMember');
const { getUserModel } = require('../models/User');
const { getTransactionModel } = require('../models/Transaction');

// Função para mover transações de uma wallet para outra
async function moveTransactions(fromWalletId, toWalletId) {
  try {
    const fromTransactionModel = getTransactionModel(fromWalletId);
    const toTransactionModel = getTransactionModel(toWalletId);
    
    // Buscar todas as transações da wallet origem
    const transactions = await fromTransactionModel.find({});
    
    if (transactions.length === 0) {
      console.log(`   ℹ️  Nenhuma transação para mover de ${fromWalletId}`);
      return 0;
    }
    
    console.log(`   📦 Movendo ${transactions.length} transações de ${fromWalletId} para ${toWalletId}...`);
    
    // Atualizar walletId de todas as transações e inserir na wallet destino
    const transactionsToInsert = transactions.map(tx => {
      const txObj = tx.toObject();
      txObj.walletId = toWalletId;
      delete txObj._id;
      return txObj;
    });
    
    if (transactionsToInsert.length > 0) {
      await toTransactionModel.insertMany(transactionsToInsert, { ordered: false });
    }
    
    // Deletar transações da wallet origem
    await fromTransactionModel.deleteMany({});
    
    console.log(`   ✅ ${transactions.length} transações movidas com sucesso`);
    return transactions.length;
  } catch (error) {
    console.error(`   ❌ Erro ao mover transações: ${error.message}`);
    throw error;
  }
}

// Função principal de consolidação
async function consolidateDuplicateWallets() {
  try {
    console.log('Conectando ao MongoDB...');
    await connectDB();
    
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();
    const User = getUserModel();
    
    // Encontrar todos os usuários
    const users = await User.find({});
    console.log(`\n📊 Encontrados ${users.length} usuários\n`);
    
    let totalConsolidated = 0;
    let totalTransactionsMoved = 0;
    
    for (const user of users) {
      // Buscar todas as wallets do usuário
      const ownedWallets = await Wallet.find({ ownerId: user.userId }).sort({ createdAt: 1 });
      
      if (ownedWallets.length <= 1) {
        // Usuário tem apenas uma wallet ou nenhuma, pular
        continue;
      }
      
      console.log(`\n👤 Usuário: ${user.name} (${user.userId})`);
      console.log(`   ⚠️  Encontradas ${ownedWallets.length} wallets pessoais`);
      
      // Escolher wallet principal:
      // 1. Se o usuário tem personalWalletId e essa wallet existe, usar ela
      // 2. Caso contrário, usar a mais antiga (primeira da lista ordenada)
      let mainWallet = null;
      
      if (user.personalWalletId) {
        mainWallet = ownedWallets.find(w => w._id.toString() === user.personalWalletId.toString());
      }
      
      if (!mainWallet) {
        mainWallet = ownedWallets[0]; // Mais antiga
      }
      
      console.log(`   ✅ Wallet principal escolhida: ${mainWallet._id} (criada em ${mainWallet.createdAt})`);
      
      // Identificar wallets duplicadas (todas exceto a principal)
      const duplicateWallets = ownedWallets.filter(w => w._id.toString() !== mainWallet._id.toString());
      console.log(`   🗑️  Wallets duplicadas a consolidar: ${duplicateWallets.length}`);
      
      // Mover transações e deletar wallets duplicadas
      for (const duplicateWallet of duplicateWallets) {
        console.log(`   🔄 Processando wallet duplicada: ${duplicateWallet._id}`);
        
        // Mover transações
        const movedCount = await moveTransactions(duplicateWallet._id, mainWallet._id);
        totalTransactionsMoved += movedCount;
        
        // Deletar membros da wallet duplicada
        await WalletMember.deleteMany({ walletId: duplicateWallet._id });
        
        // Deletar convites da wallet duplicada
        const { getInviteModel } = require('../models/Invite');
        const Invite = getInviteModel();
        await Invite.deleteMany({ walletId: duplicateWallet._id });
        
        // Deletar a wallet duplicada
        await Wallet.findByIdAndDelete(duplicateWallet._id);
        console.log(`   ✅ Wallet duplicada ${duplicateWallet._id} deletada`);
      }
      
      // Atualizar personalWalletId do usuário
      if (user.personalWalletId?.toString() !== mainWallet._id.toString()) {
        user.personalWalletId = mainWallet._id;
        await user.save();
        console.log(`   ✅ personalWalletId atualizado para ${mainWallet._id}`);
      }
      
      totalConsolidated += duplicateWallets.length;
      console.log(`   ✅ Consolidação concluída para usuário ${user.name}`);
    }
    
    console.log(`\n\n📊 RESUMO DA CONSOLIDAÇÃO:`);
    console.log(`   👥 Usuários processados: ${users.length}`);
    console.log(`   🔄 Wallets duplicadas consolidadas: ${totalConsolidated}`);
    console.log(`   📦 Transações movidas: ${totalTransactionsMoved}`);
    console.log(`\n✅ Consolidação concluída com sucesso!\n`);
    
  } catch (error) {
    console.error('❌ Erro durante consolidação:', error);
    throw error;
  } finally {
    await mongoose.connection.close();
    console.log('🔌 Desconectado do MongoDB');
  }
}

// Executar script
if (require.main === module) {
  consolidateDuplicateWallets()
    .then(() => {
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Erro fatal:', error);
      process.exit(1);
    });
}

module.exports = { consolidateDuplicateWallets };

