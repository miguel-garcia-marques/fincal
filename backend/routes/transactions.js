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
          // Verificar se o dia existe no mês antes de criar a transação
          const daysInMonth = new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, 0).getDate();
          const targetDay = transaction.dayOfMonth;
          
          // Se o dia do mês da transação existe neste mês e corresponde ao dia atual
          if (targetDay <= daysInMonth && currentDate.getDate() === targetDay) {
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

// POST importar transações em bulk
router.post('/bulk', async (req, res) => {
  try {
    const Transaction = getTransactionModel(req.userId);
    const { transactions } = req.body;
    
    if (!Array.isArray(transactions)) {
      return res.status(400).json({ message: 'transactions deve ser um array' });
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
          userId: req.userId,
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

module.exports = router;

