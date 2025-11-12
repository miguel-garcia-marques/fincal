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

    await connectDB();
    
    const db = mongoose.connection.db;
    const dbName = db.databaseName;

    // Listar todas as collections
    const collections = await db.listCollections().toArray();

    // Encontrar collections antigas que seguem o padrão transactions_<userId>
    const oldCollections = collections.filter(coll => 
      coll.name.startsWith('transactions_') && coll.name !== 'transactions'
    );

    if (oldCollections.length === 0) {

      process.exit(0);
    }
    
    const Wallet = getWalletModel();
    
    let totalMigrated = 0;
    let totalErrors = 0;
    
    for (const oldColl of oldCollections) {
      const oldCollectionName = oldColl.name;
      const userId = oldCollectionName.replace('transactions_', '');

      // Contar documentos na collection antiga
      const oldCollection = db.collection(oldCollectionName);
      const count = await oldCollection.countDocuments({});

      if (count === 0) {

        continue;
      }
      
      // Encontrar ou criar wallet pessoal para este usuário
      let personalWallet = await Wallet.findOne({ ownerId: userId });
      
      if (!personalWallet) {

        personalWallet = await Wallet.create({
          name: 'Minha Carteira Calendário',
          ownerId: userId,
        });

      } else {

      }
      
      // Buscar todas as transações da collection antiga
      const oldTransactions = await oldCollection.find({}).toArray();

      // Obter o modelo de transações para esta wallet (uma vez, antes do loop)
      const TransactionModel = getTransactionModel(personalWallet._id);
      
      let migrated = 0;
      let errors = 0;
      
      for (const oldTx of oldTransactions) {
        try {
          // Verificar se a transação já existe na collection nova (por id)
          const existing = await TransactionModel.findOne({ id: oldTx.id });
          
          if (existing) {

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

          }
        } catch (error) {
          errors++;

          // Se for erro de duplicação, apenas avisar
          if (error.code === 11000) {
            errors--; // Não contar como erro real
          }
        }
      }

      totalMigrated += migrated;
      totalErrors += errors;
    }

    // Verificar resultado final - listar todas as collections de transações

    const allCollections = await db.listCollections().toArray();
    const transactionCollections = allCollections.filter(coll => 
      coll.name.startsWith('transactions_') && coll.name !== 'transactions'
    );
    for (const coll of transactionCollections) {
      const count = await db.collection(coll.name).countDocuments({});

    }
    
    // Opcional: perguntar se quer deletar collections antigas

    for (const oldColl of oldCollections) {
      const count = await db.collection(oldColl.name).countDocuments({});

    }

    process.exit(0);
  } catch (error) {

    process.exit(1);
  }
}

// Executar migração
migrateOldCollections();
