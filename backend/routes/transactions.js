const express = require('express');
const router = express.Router();
const { getTransactionModel } = require('../models/Transaction');
const { authenticateUser } = require('../middleware/auth');

// Aplicar middleware de autenticação em todas as rotas
router.use(authenticateUser);

// GET todas as transações
router.get('/', async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.userId);
    const transactions = await Transaction.find({ userId: req.userId }).sort({ date: 1 });
    res.json(transactions);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// GET transações em um período
router.get('/range', async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.userId);
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

    // Buscar todas as transações (incluindo periódicas) do usuário
    const allTransactions = await Transaction.find({ userId: req.userId });
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
        
        while (currentDate <= end) {
          const zellerDay = getDayOfWeek(
            currentDate.getDate(),
            currentDate.getMonth() + 1,
            currentDate.getFullYear()
          );
          // Zeller: 0=Sáb, 1=Dom, 2=Seg...
          // Formulário usa: 0=Sáb, 1=Dom, 2=Seg... (mesmo formato)
          const formDayOfWeek = zellerDay;
          
          if (formDayOfWeek === transaction.dayOfWeek) {
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
        
        let currentDate = new Date(start);
        currentDate.setHours(0, 0, 0, 0);
        
        // Criar uma cópia do end apenas com a data (sem hora) para comparação
        const endDateOnly = new Date(end.getFullYear(), end.getMonth(), end.getDate());
        endDateOnly.setHours(0, 0, 0, 0);
        
        while (currentDate <= end) {
          if (currentDate.getDate() === transaction.dayOfMonth) {
            const generatedTransaction = transaction.toObject();
            generatedTransaction._id = `${transaction._id}_${currentDate.getTime()}`;
            generatedTransaction.id = `${transaction.id}_${currentDate.getTime()}`;
            generatedTransaction.date = new Date(currentDate);
            generatedTransaction.frequency = 'monthly'; // Manter informação de periodicidade
            generatedTransaction.dayOfWeek = null;
            generatedTransaction.dayOfMonth = transaction.dayOfMonth; // Manter informação do dia
            result.push(generatedTransaction);
          }
          
          // Verificar se já chegamos ao último dia antes de incrementar
          const currentDateOnly = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate());
          if (currentDateOnly.getTime() >= endDateOnly.getTime()) {
            break;
          }
          
          currentDate.setDate(currentDate.getDate() + 1);
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
router.post('/', async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.userId);
    const transactionData = { ...req.body, userId: req.userId };
    
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
router.delete('/:id', async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.userId);
    const transaction = await Transaction.findOneAndDelete({ 
      id: req.params.id,
      userId: req.userId 
    });
    
    if (!transaction) {
      return res.status(404).json({ message: 'Transação não encontrada' });
    }
    
    res.json({ message: 'Transação deletada com sucesso' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// PUT atualizar transação
router.put('/:id', async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.userId);
    const transaction = await Transaction.findOneAndUpdate(
      { id: req.params.id, userId: req.userId },
      { ...req.body, userId: req.userId },
      { new: true, runValidators: true }
    );
    
    if (!transaction) {
      return res.status(404).json({ message: 'Transação não encontrada' });
    }
    
    res.json(transaction);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

module.exports = router;

