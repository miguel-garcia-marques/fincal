const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const { getTransactionModel } = require('../models/Transaction');
const { authenticateUser } = require('../middleware/auth');
const { checkWalletAccess, checkWritePermission } = require('../middleware/walletAuth');
const {
  validateTransaction,
  validateTransactionRange,
  validateTransactionId,
  validateBulkTransactions
} = require('../middleware/validation');

// Aplicar middleware de autenticação em todas as rotas
router.use(authenticateUser);

// Middleware para verificar walletId e permissões
const requireWalletId = async (req, res, next) => {
  try {
    const walletId = req.query.walletId || req.body.walletId;
    
    if (!walletId) {
      return res.status(400).json({ message: 'Wallet ID é obrigatório' });
    }

    req.query.walletId = walletId;
    req.body.walletId = walletId;
    
    // Verificar acesso à wallet
    req.params.walletId = walletId;
    
    // Usar checkWalletAccess de forma correta
    const { getWalletModel } = require('../models/Wallet');
    const { getWalletMemberModel } = require('../models/WalletMember');
    
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();

    const wallet = await Wallet.findById(walletId);
    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    if (wallet.ownerId === req.userId) {
      req.walletPermission = 'owner';
      req.walletId = walletId;
      return next();
    }

    const member = await WalletMember.findOne({ 
      walletId: walletId, 
      userId: req.userId 
    });

    if (!member) {
      return res.status(403).json({ message: 'Você não tem acesso a esta wallet' });
    }

    req.walletPermission = member.permission;
    req.walletId = walletId;
    next();
  } catch (error) {
    return res.status(500).json({ message: 'Erro ao verificar acesso à wallet' });
  }
};

// GET todas as transações
router.get('/', requireWalletId, async (req, res) => {
  try {
    // Usar collection específica para este walletId
    const Transaction = getTransactionModel(req.walletId);
    
    // Buscar todas as transações da collection desta wallet
    const transactions = await Transaction.find({}).sort({ date: 1 });
    
    res.json(transactions);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// GET transações em um período
router.get('/range', validateTransactionRange, requireWalletId, async (req, res) => {
  try {
    // Usar collection específica para este walletId
    const Transaction = getTransactionModel(req.walletId);
    const { startDate, endDate } = req.query;
    
    if (!startDate || !endDate) {
      return res.status(400).json({ message: 'startDate and endDate are required' });
    }

    // Parse das datas garantindo que são tratadas como data local (sem timezone)
    const startParts = startDate.split('-');
    const endParts = endDate.split('-');
    const start = new Date(
      parseInt(startParts[0]),
      parseInt(startParts[1]) - 1, // Mês é 0-indexed
      parseInt(startParts[2])
    );
    start.setHours(0, 0, 0, 0);
    
    const end = new Date(
      parseInt(endParts[0]),
      parseInt(endParts[1]) - 1, // Mês é 0-indexed
      parseInt(endParts[2])
    );
    end.setHours(23, 59, 59, 999); // Incluir o dia inteiro

    // Buscar todas as transações (incluindo periódicas) da collection desta wallet
    const allTransactions = await Transaction.find({});
    
    const result = [];

    for (const transaction of allTransactions) {
      if (transaction.frequency === 'unique') {
        // Transações únicas: verificar se estão no período
        const transactionDate = new Date(transaction.date);
        // Garantir que a data da transação é apenas data (sem hora)
        transactionDate.setHours(0, 0, 0, 0);
        transactionDate.setMinutes(0, 0, 0);
        transactionDate.setSeconds(0, 0);
        transactionDate.setMilliseconds(0);
        
        // Comparar apenas as datas (ano, mês, dia)
        const txYear = transactionDate.getFullYear();
        const txMonth = transactionDate.getMonth();
        const txDay = transactionDate.getDate();
        const txDateOnly = new Date(txYear, txMonth, txDay);
        
        if (txDateOnly >= start && txDateOnly <= end) {
          result.push(transaction);
        }
      } else if (transaction.frequency === 'weekly') {
        // Transações semanais: gerar para todas as semanas no período
        if (transaction.dayOfWeek === null || transaction.dayOfWeek === undefined) continue;
        
        const { getDayOfWeek } = require('../utils/zeller');
        let currentDate = new Date(start);
        currentDate.setHours(0, 0, 0, 0);
        
        // Criar uma cópia do end apenas com a data (sem hora) para comparação
        const endDateOnly = new Date(end.getFullYear(), end.getMonth(), end.getDate());
        endDateOnly.setHours(0, 0, 0, 0);
        
        // Normalizar excludedDates para comparação (apenas data, sem hora)
        const excludedDatesNormalized = (transaction.excludedDates || []).map(d => {
          const date = new Date(d);
          return new Date(date.getFullYear(), date.getMonth(), date.getDate());
        });
        
        // Função auxiliar para verificar se uma data está excluída
        const isDateExcluded = (date) => {
          const dateNormalized = new Date(date.getFullYear(), date.getMonth(), date.getDate());
          return excludedDatesNormalized.some(excluded => 
            excluded.getTime() === dateNormalized.getTime()
          );
        };
        
        while (currentDate <= end) {
          const zellerDay = getDayOfWeek(
            currentDate.getDate(),
            currentDate.getMonth() + 1,
            currentDate.getFullYear()
          );
          // Zeller: 0=Sáb, 1=Dom, 2=Seg...
          // Formulário usa: 0=Sáb, 1=Dom, 2=Seg... (mesmo formato)
          const formDayOfWeek = zellerDay;
          
          if (formDayOfWeek === transaction.dayOfWeek && !isDateExcluded(currentDate)) {
            const generatedTransaction = transaction.toObject();
            generatedTransaction._id = `${transaction._id}_${currentDate.getTime()}`;
            generatedTransaction.id = `${transaction.id}_${currentDate.getTime()}`;
            generatedTransaction.date = new Date(currentDate);
            generatedTransaction.frequency = 'weekly'; // Manter informação de periodicidade
            generatedTransaction.dayOfWeek = transaction.dayOfWeek; // Manter informação do dia
            generatedTransaction.dayOfMonth = null;
            result.push(generatedTransaction);
          }
          
          // Verificar se já chegamos ao último dia antes de incrementar
          const currentDateOnly = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate());
          if (currentDateOnly.getTime() >= endDateOnly.getTime()) {
            break;
          }
          
          currentDate.setDate(currentDate.getDate() + 1);
        }
      } else if (transaction.frequency === 'monthly') {
        // Transações mensais: gerar para todos os meses no período
        if (transaction.dayOfMonth === null || transaction.dayOfMonth === undefined) continue;
        
        const targetDay = transaction.dayOfMonth;
        
        // Normalizar excludedDates para comparação (apenas data, sem hora)
        const excludedDatesNormalized = (transaction.excludedDates || []).map(d => {
          const date = new Date(d);
          return new Date(date.getFullYear(), date.getMonth(), date.getDate());
        });
        
        // Função auxiliar para verificar se uma data está excluída
        const isDateExcluded = (date) => {
          const dateNormalized = new Date(date.getFullYear(), date.getMonth(), date.getDate());
          return excludedDatesNormalized.some(excluded => 
            excluded.getTime() === dateNormalized.getTime()
          );
        };
        
        // Iterar pelos meses no período, não pelos dias
        let currentMonth = new Date(start.getFullYear(), start.getMonth(), 1);
        const endMonth = new Date(end.getFullYear(), end.getMonth(), 1);
        
        while (currentMonth <= endMonth) {
          // Verificar quantos dias tem este mês
          const daysInMonth = new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 0).getDate();
          
          // Se o dia especificado não existe no mês, usar o último dia do mês
          const actualDay = targetDay <= daysInMonth ? targetDay : daysInMonth;
          
          // Criar a data da transação para este mês
          const transactionDate = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), actualDay);
          transactionDate.setHours(0, 0, 0, 0);
          
          // Verificar se a data da transação está dentro do período solicitado e não está excluída
          if (transactionDate >= start && transactionDate <= end && !isDateExcluded(transactionDate)) {
            const generatedTransaction = transaction.toObject();
            generatedTransaction._id = `${transaction._id}_${transactionDate.getTime()}`;
            generatedTransaction.id = `${transaction.id}_${transactionDate.getTime()}`;
            generatedTransaction.date = transactionDate;
            generatedTransaction.frequency = 'monthly'; // Manter informação de periodicidade
            generatedTransaction.dayOfWeek = null;
            generatedTransaction.dayOfMonth = transaction.dayOfMonth; // Manter informação do dia original
            result.push(generatedTransaction);
          }
          
          // Avançar para o próximo mês
          currentMonth = new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 1);
        }
      }
    }

    // Ordenar por data
    result.sort((a, b) => new Date(a.date) - new Date(b.date));
    
    res.json(result);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar nova transação
router.post('/', validateTransaction, requireWalletId, checkWritePermission, async (req, res) => {
  try {
    // Usar collection específica para este walletId
    const Transaction = getTransactionModel(req.walletId);
    const transactionData = { 
      ...req.body, 
      userId: req.userId, // Mantido para compatibilidade
      walletId: req.walletId,
      createdBy: req.userId
    };
    
    // Validar percentagens se for salário
    if (transactionData.isSalary && transactionData.salaryAllocation) {
      const { gastosPercent, lazerPercent, poupancaPercent } = transactionData.salaryAllocation;
      const total = gastosPercent + lazerPercent + poupancaPercent;
      
      if (Math.abs(total - 100) > 0.1) {
        return res.status(400).json({ 
          message: 'As percentagens devem somar 100%' 
        });
      }
    }

    // Validar categoria de despesa
    if (transactionData.type === 'despesa' && !transactionData.expenseBudgetCategory) {
      return res.status(400).json({ 
        message: 'Categoria de orçamento é obrigatória para despesas' 
      });
    }

    // Validar periodicidade
    if (transactionData.frequency === 'weekly' && transactionData.dayOfWeek === null) {
      return res.status(400).json({ 
        message: 'Dia da semana é obrigatório para transações semanais' 
      });
    }

    if (transactionData.frequency === 'monthly' && transactionData.dayOfMonth === null) {
      return res.status(400).json({ 
        message: 'Dia do mês é obrigatório para transações mensais' 
      });
    }

    const transaction = new Transaction(transactionData);
    await transaction.save();
    
    res.status(201).json(transaction);
  } catch (error) {
    if (error.code === 11000) {
      res.status(400).json({ message: 'Transação com este ID já existe' });
    } else {
      res.status(500).json({ message: error.message });
    }
  }
});

// DELETE transação
router.delete('/:id', validateTransactionId, requireWalletId, checkWritePermission, async (req, res) => {
  try {
    // Usar collection específica para este walletId
    const Transaction = getTransactionModel(req.walletId);
    const transaction = await Transaction.findOne({ 
      id: req.params.id
    });
    
    if (!transaction) {
      return res.status(404).json({ message: 'Transação não encontrada' });
    }

    // Verificar se é o criador ou tem permissão de owner
    if (transaction.createdBy !== req.userId && req.walletPermission !== 'owner') {
      return res.status(403).json({ message: 'Você só pode deletar transações que você criou' });
    }
    
    await Transaction.findOneAndDelete({ 
      id: req.params.id
    });
    
    res.json({ message: 'Transação deletada com sucesso' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// PUT atualizar transação
router.put('/:id', validateTransactionId, validateTransaction, requireWalletId, checkWritePermission, async (req, res) => {
  try {
    // Usar collection específica para este walletId
    const Transaction = getTransactionModel(req.walletId);
    const existingTransaction = await Transaction.findOne({ 
      id: req.params.id
    });
    
    if (!existingTransaction) {
      return res.status(404).json({ message: 'Transação não encontrada' });
    }

    // Verificar se é o criador ou tem permissão de owner
    if (existingTransaction.createdBy !== req.userId && req.walletPermission !== 'owner') {
      return res.status(403).json({ message: 'Você só pode atualizar transações que você criou' });
    }

    const transaction = await Transaction.findOneAndUpdate(
      { id: req.params.id },
      { ...req.body, userId: req.userId, walletId: req.walletId },
      { new: true, runValidators: true }
    );
    
    res.json(transaction);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar exceção de transação periódica (editar ocorrência específica)
router.post('/:id/exclude-date', requireWalletId, checkWritePermission, async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.walletId);
    const { date } = req.body;
    
    if (!date) {
      return res.status(400).json({ message: 'Data é obrigatória' });
    }

    const existingTransaction = await Transaction.findOne({ 
      id: req.params.id
    });
    
    if (!existingTransaction) {
      return res.status(404).json({ message: 'Transação não encontrada' });
    }

    // Verificar se é uma transação periódica
    if (existingTransaction.frequency === 'unique') {
      return res.status(400).json({ message: 'Apenas transações periódicas podem ter datas excluídas' });
    }

    // Verificar se é o criador ou tem permissão de owner
    if (existingTransaction.createdBy !== req.userId && req.walletPermission !== 'owner') {
      return res.status(403).json({ message: 'Você só pode modificar transações que você criou' });
    }

    // Parse da data
    const dateParts = date.split('-');
    const excludeDate = new Date(
      parseInt(dateParts[0]),
      parseInt(dateParts[1]) - 1,
      parseInt(dateParts[2])
    );
    excludeDate.setHours(0, 0, 0, 0);

    // Normalizar excludedDates existentes
    const excludedDates = (existingTransaction.excludedDates || []).map(d => {
      const date = new Date(d);
      return new Date(date.getFullYear(), date.getMonth(), date.getDate());
    });

    // Verificar se a data já está excluída
    const excludeDateNormalized = new Date(excludeDate.getFullYear(), excludeDate.getMonth(), excludeDate.getDate());
    const alreadyExcluded = excludedDates.some(excluded => 
      excluded.getTime() === excludeDateNormalized.getTime()
    );

    if (alreadyExcluded) {
      return res.status(400).json({ message: 'Esta data já está excluída' });
    }

    // Adicionar a data à lista de excluídas
    excludedDates.push(excludeDateNormalized);

    // Atualizar a transação
    const updatedTransaction = await Transaction.findOneAndUpdate(
      { id: req.params.id },
      { excludedDates: excludedDates },
      { new: true, runValidators: true }
    );
    
    res.json(updatedTransaction);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar exceção de transação periódica (substituir ocorrência específica)
router.post('/:id/exception', requireWalletId, checkWritePermission, async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.walletId);
    const { date, ...newTransactionData } = req.body;
    
    if (!date) {
      return res.status(400).json({ message: 'Data da ocorrência original é obrigatória' });
    }

    const originalTransaction = await Transaction.findOne({ 
      id: req.params.id
    });
    
    if (!originalTransaction) {
      return res.status(404).json({ message: 'Transação original não encontrada' });
    }

    // Verificar se é uma transação periódica
    if (originalTransaction.frequency === 'unique') {
      return res.status(400).json({ message: 'Apenas transações periódicas podem ter exceções' });
    }

    // Verificar permissões
    if (originalTransaction.createdBy !== req.userId && req.walletPermission !== 'owner') {
      return res.status(403).json({ message: 'Você só pode modificar transações que você criou' });
    }

    // 1. Adicionar data à lista de excluídas da transação original
    const dateParts = date.split('-');
    const excludeDate = new Date(
      parseInt(dateParts[0]),
      parseInt(dateParts[1]) - 1,
      parseInt(dateParts[2])
    );
    excludeDate.setHours(0, 0, 0, 0);

    const excludedDates = (originalTransaction.excludedDates || []).map(d => {
      const date = new Date(d);
      return new Date(date.getFullYear(), date.getMonth(), date.getDate());
    });

    const excludeDateNormalized = new Date(excludeDate.getFullYear(), excludeDate.getMonth(), excludeDate.getDate());
    const alreadyExcluded = excludedDates.some(excluded => 
      excluded.getTime() === excludeDateNormalized.getTime()
    );

    if (!alreadyExcluded) {
      excludedDates.push(excludeDateNormalized);
      await Transaction.findOneAndUpdate(
        { id: req.params.id },
        { excludedDates: excludedDates },
        { new: true }
      );
    }

    // 2. Criar nova transação única
    const newTransaction = new Transaction({
      ...newTransactionData,
      id: newTransactionData.id || Date.now().toString(), // Garantir ID
      userId: req.userId,
      walletId: req.walletId,
      createdBy: req.userId,
      frequency: 'unique', // Forçar ser única
      dayOfWeek: undefined,
      dayOfMonth: undefined,
      excludedDates: []
    });

    await newTransaction.save();
    
    res.status(201).json(newTransaction);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST importar transações em bulk
router.post('/bulk', validateBulkTransactions, requireWalletId, checkWritePermission, async (req, res) => {
  try {
    // Usar collection específica para este walletId
    const Transaction = getTransactionModel(req.walletId);
    const { transactions } = req.body;
    
    // Validação adicional de tamanho (já validado pelo middleware, mas manter para compatibilidade)
    if (!Array.isArray(transactions)) {
      return res.status(400).json({ message: 'transactions deve ser um array' });
    }
    
    if (transactions.length > 1000) {
      return res.status(400).json({ message: 'Máximo de 1000 transações por importação' });
    }

    // Mapear dias da semana de string para número
    // Zeller: 0=Sábado, 1=Domingo, 2=Segunda, 3=Terça, 4=Quarta, 5=Quinta, 6=Sexta
    const dayOfWeekMap = {
      'domingo': 1,
      'segunda': 2,
      'terça': 2,
      'terca': 2,
      'quarta': 4,
      'quinta': 5,
      'sexta': 6,
      'sábado': 0,
      'sabado': 0,
      'dom': 1,
      'seg': 2,
      'ter': 2,
      'qua': 4,
      'qui': 5,
      'sex': 6,
      'sab': 0,
    };

    const convertedTransactions = [];
    const errors = [];

    for (let i = 0; i < transactions.length; i++) {
      const tx = transactions[i];
      try {
        // Converter periodicity para frequency
        let frequency = 'unique';
        if (tx.periodicity === 'mensal') {
          frequency = 'monthly';
        } else if (tx.periodicity === 'semanal') {
          frequency = 'weekly';
        }

        // Converter day/dayofWeek
        let dayOfWeek = null;
        let dayOfMonth = null;
        if (frequency === 'weekly') {
          // Aceitar dayofWeek ou day (para compatibilidade)
          const dayValue = tx.dayofWeek || tx.day;
          if (dayValue) {
            const dayStr = dayValue.toString().toLowerCase().trim();
            dayOfWeek = dayOfWeekMap[dayStr];
            if (dayOfWeek === undefined) {
              throw new Error(`Dia da semana inválido: "${dayValue}". Valores válidos: domingo, segunda, terça, quarta, quinta, sexta, sábado`);
            }
          } else {
            throw new Error('Dia da semana é obrigatório para transações semanais (use "dayofWeek" ou "day")');
          }
        } else if (frequency === 'monthly') {
          if (tx.day !== undefined && tx.day !== null) {
            dayOfMonth = parseInt(tx.day);
            if (isNaN(dayOfMonth) || dayOfMonth < 1 || dayOfMonth > 31) {
              throw new Error(`Dia do mês inválido: ${tx.day}. Deve ser um número entre 1 e 31`);
            }
          } else {
            throw new Error('Dia do mês é obrigatório para transações mensais (use "day" com um número)');
          }
        }

        // Converter value para amount
        const amount = parseFloat(tx.value || tx.amount || 0);
        if (isNaN(amount) || amount <= 0) {
          throw new Error(`Valor inválido: ${tx.value || tx.amount}. Deve ser um número maior que zero`);
        }

        // Converter salaryAllocation se existir
        let salaryAllocation = null;
        if (tx.salaryAllocation) {
          const gastos = parseFloat(tx.salaryAllocation.gastos || tx.salaryAllocation.gastosPercent || 0);
          const lazer = parseFloat(tx.salaryAllocation.lazer || tx.salaryAllocation.lazerPercent || 0);
          const poupanca = parseFloat(tx.salaryAllocation.poupanca || tx.salaryAllocation.poupancaPercent || 0);
          salaryAllocation = { gastosPercent: gastos, lazerPercent: lazer, poupancaPercent: poupanca };
        }

        // Converter budgetCategory para expenseBudgetCategory
        const expenseBudgetCategory = tx.budgetCategory || null;

        // Data padrão: usar data atual se não especificada
        let date = new Date();
        if (tx.date) {
          date = new Date(tx.date);
        } else if (frequency === 'unique') {
          // Para transações únicas sem data, usar data atual
          date = new Date();
        } else {
          // Para transações periódicas, usar data atual como referência
          date = new Date();
        }
        date.setHours(0, 0, 0, 0);

        // Gerar ID único
        const id = `import_${Date.now()}_${i}_${Math.random().toString(36).substr(2, 9)}`;

        const convertedTx = {
          id,
          userId: req.userId, // Mantido para compatibilidade
          walletId: req.walletId,
          createdBy: req.userId,
          type: tx.type,
          date,
          description: tx.description || null,
          amount,
          category: tx.category,
          isSalary: tx.salary === true,
          salaryAllocation,
          expenseBudgetCategory,
          frequency,
          dayOfWeek,
          dayOfMonth,
          person: tx.person || null,
        };

        convertedTransactions.push(convertedTx);
      } catch (error) {
        errors.push({ 
          index: i, 
          error: error.message, 
          transaction: tx,
          missingFields: _identifyMissingFields(tx, error.message)
        });
      }
    }

    // Função auxiliar para identificar campos faltantes
    function _identifyMissingFields(tx, errorMsg) {
      const missing = [];
      if (!tx.type) missing.push('type');
      if (!tx.category) missing.push('category');
      if (!tx.value && !tx.amount) missing.push('value');
      
      // Para transações semanais, verificar se dayofWeek ou day está presente e é válido
      if (tx.periodicity === 'semanal') {
        const dayValue = tx.dayofWeek || tx.day;
        if (!dayValue) {
          missing.push('dayofWeek');
        } else {
          const dayStr = dayValue.toString().toLowerCase().trim();
          if (!dayOfWeekMap[dayStr]) {
            missing.push('dayofWeek'); // Campo existe mas valor é inválido
          }
        }
      }
      
      // Para transações mensais, verificar se day está presente e é válido
      if (tx.periodicity === 'mensal') {
        if (!tx.day) {
          missing.push('day');
        } else {
          const dayNum = parseInt(tx.day);
          if (isNaN(dayNum) || dayNum < 1 || dayNum > 31) {
            missing.push('day'); // Campo existe mas valor é inválido
          }
        }
      }
      
      if (tx.type === 'despesa' && !tx.budgetCategory) missing.push('budgetCategory');
      return missing;
    }

    if (errors.length > 0 && convertedTransactions.length === 0) {
      return res.status(400).json({ 
        message: 'Nenhuma transação foi convertida com sucesso',
        errors 
      });
    }

    // Inserir todas as transações
    const savedTransactions = await Transaction.insertMany(convertedTransactions);

    res.status(201).json({
      message: `${savedTransactions.length} transações importadas com sucesso`,
      imported: savedTransactions.length,
      errors: errors.length > 0 ? errors : undefined,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST processar imagem de fatura com IA
router.post('/extract-from-image', requireWalletId, async (req, res) => {
  try {
    const { imageBase64 } = req.body;

    if (!imageBase64) {
      return res.status(400).json({ message: 'Imagem em base64 é obrigatória' });
    }

    const { processInvoiceImage } = require('../utils/geminiService');
    const extractedData = await processInvoiceImage(imageBase64);

    res.json({
      success: true,
      data: extractedData
    });
  } catch (error) {
    console.error('Erro ao processar imagem:', error);
    res.status(500).json({ 
      message: error.message || 'Erro ao processar imagem da fatura',
      success: false
    });
  }
});

module.exports = router;
