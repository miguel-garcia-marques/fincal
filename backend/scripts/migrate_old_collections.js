/**
 * Script para migrar transações de collections antigas (por userId) para collections por walletId
 * 
 * Este script encontra todas as collections que seguem o padrão transactions_<userId>
 * e migra as transações para collections específicas por walletId (transactions_<walletId>)
 */

require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/database');
const { getTransactionModel } = require('../models/Transaction');
const { getWalletModel } = require('../models/Wallet');

async function migrateOldCollections() {
  try {
    console.log('Conectando ao MongoDB...');
    await connectDB();
    
    const db = mongoose.connection.db;
    const dbName = db.databaseName;
    console.log(`\n📊 Database: ${dbName}`);
    
    // Listar todas as collections
    const collections = await db.listCollections().toArray();
    console.log(`\n📁 Collections encontradas: ${collections.length}`);
    
    // Encontrar collections antigas que seguem o padrão transactions_<userId>
    const oldCollections = collections.filter(coll => 
      coll.name.startsWith('transactions_') && coll.name !== 'transactions'
    );
    
    console.log(`\n🔍 Collections antigas encontradas: ${oldCollections.length}`);
    
    if (oldCollections.length === 0) {
      console.log('✅ Nenhuma collection antiga encontrada para migrar!');
      process.exit(0);
    }
    
    const Wallet = getWalletModel();
    
    let totalMigrated = 0;
    let totalErrors = 0;
    
    for (const oldColl of oldCollections) {
      const oldCollectionName = oldColl.name;
      const userId = oldCollectionName.replace('transactions_', '');
      
      console.log(`\n📦 Processando collection: ${oldCollectionName}`);
      console.log(`   UserId extraído: ${userId}`);
      
      // Contar documentos na collection antiga
      const oldCollection = db.collection(oldCollectionName);
      const count = await oldCollection.countDocuments({});
      console.log(`   Documentos na collection antiga: ${count}`);
      
      if (count === 0) {
        console.log(`   ⏭️  Collection vazia, pulando...`);
        continue;
      }
      
      // Encontrar ou criar wallet pessoal para este usuário
      let personalWallet = await Wallet.findOne({ ownerId: userId });
      
      if (!personalWallet) {
        console.log(`   📝 Criando wallet pessoal para userId: ${userId}`);
        personalWallet = await Wallet.create({
          name: 'Minha Carteira Calendário',
          ownerId: userId,
        });
        console.log(`   ✅ Wallet criada: ${personalWallet._id}`);
      } else {
        console.log(`   ✅ Wallet pessoal encontrada: ${personalWallet._id}`);
      }
      
      // Buscar todas as transações da collection antiga
      const oldTransactions = await oldCollection.find({}).toArray();
      console.log(`   📥 Transações encontradas: ${oldTransactions.length}`);
      
      // Obter o modelo de transações para esta wallet (uma vez, antes do loop)
      const TransactionModel = getTransactionModel(personalWallet._id);
      
      let migrated = 0;
      let errors = 0;
      
      for (const oldTx of oldTransactions) {
        try {
          // Verificar se a transação já existe na collection nova (por id)
          const existing = await TransactionModel.findOne({ id: oldTx.id });
          
          if (existing) {
            console.log(`   ⚠️  Transação ${oldTx.id} já existe, pulando...`);
            continue;
          }
          
          // Preparar dados da transação para migração
          const transactionData = {
            id: oldTx.id,
            userId: oldTx.userId || userId,
            walletId: personalWallet._id, // Usar wallet pessoal (já é ObjectId)
            createdBy: oldTx.createdBy || oldTx.userId || userId,
            type: oldTx.type,
            date: oldTx.date,
            description: oldTx.description,
            amount: oldTx.amount,
            category: oldTx.category,
            isSalary: oldTx.isSalary || false,
            salaryAllocation: oldTx.salaryAllocation,
            expenseBudgetCategory: oldTx.expenseBudgetCategory,
            frequency: oldTx.frequency || 'unique',
            dayOfWeek: oldTx.dayOfWeek,
            dayOfMonth: oldTx.dayOfMonth,
            person: oldTx.person,
          };
          
          // Criar nova transação na collection desta wallet
          const newTransaction = new TransactionModel(transactionData);
          await newTransaction.save();
          
          migrated++;
          
          if (migrated % 10 === 0) {
            console.log(`   ✅ Migradas ${migrated}/${oldTransactions.length} transações...`);
          }
        } catch (error) {
          errors++;
          console.error(`   ❌ Erro ao migrar transação ${oldTx._id}: ${error.message}`);
          
          // Se for erro de duplicação, apenas avisar
          if (error.code === 11000) {
            console.log(`   ⚠️  Transação ${oldTx.id} já existe (duplicada), pulando...`);
            errors--; // Não contar como erro real
          }
        }
      }
      
      console.log(`   ✅ Migração concluída: ${migrated} transações migradas, ${errors} erros`);
      totalMigrated += migrated;
      totalErrors += errors;
    }
    
    console.log(`\n\n=== RESUMO DA MIGRAÇÃO ===`);
    console.log(`✅ Total de transações migradas: ${totalMigrated}`);
    console.log(`❌ Total de erros: ${totalErrors}`);
    
    // Verificar resultado final - listar todas as collections de transações
    console.log(`\n📊 Collections de transações criadas:`);
    const allCollections = await db.listCollections().toArray();
    const transactionCollections = allCollections.filter(coll => 
      coll.name.startsWith('transactions_') && coll.name !== 'transactions'
    );
    for (const coll of transactionCollections) {
      const count = await db.collection(coll.name).countDocuments({});
      console.log(`   - ${coll.name}: ${count} transações`);
    }
    
    // Opcional: perguntar se quer deletar collections antigas
    console.log(`\n💡 As collections antigas ainda existem. Você pode deletá-las manualmente se quiser.`);
    console.log(`   Collections antigas:`);
    for (const oldColl of oldCollections) {
      const count = await db.collection(oldColl.name).countDocuments({});
      console.log(`   - ${oldColl.name}: ${count} documentos`);
    }
    
    console.log('\n✅ Migração concluída!\n');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Erro durante migração:', error);
    process.exit(1);
  }
}

// Executar migração
migrateOldCollections();

