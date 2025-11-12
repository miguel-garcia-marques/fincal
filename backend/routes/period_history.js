const express = require('express');
const router = express.Router();
const { getPeriodHistoryModel } = require('../models/PeriodHistory');
const { authenticateUser } = require('../middleware/auth');
const { validatePeriodHistory, validatePeriodId } = require('../middleware/validation');

// Aplicar middleware de autenticação em todas as rotas
router.use(authenticateUser);

// GET todas as histórias de períodos do usuário
router.get('/', async (req, res) => {
  try {
    const PeriodHistory = getPeriodHistoryModel(req.userId);
    const periods = await PeriodHistory.find({ userId: req.userId })
      .sort({ startDate: -1 }); // Mais recentes primeiro
    res.json(periods);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// GET uma história de período específica por ID
router.get('/:id', validatePeriodId, async (req, res) => {
  try {
    const PeriodHistory = getPeriodHistoryModel(req.userId);
    const period = await PeriodHistory.findOne({ 
      id: req.params.id,
      userId: req.userId 
    });
    
    if (!period) {
      return res.status(404).json({ message: 'Período não encontrado' });
    }
    
    res.json(period);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar nova história de período
router.post('/', validatePeriodHistory, async (req, res) => {
  try {
    const PeriodHistory = getPeriodHistoryModel(req.userId);
    const { startDate, endDate, transactionIds, name } = req.body;
    
    if (!startDate || !endDate) {
      return res.status(400).json({ 
        message: 'startDate e endDate são obrigatórios' 
      });
    }

    // Parse das datas
    const startParts = startDate.split('-');
    const endParts = endDate.split('-');
    const start = new Date(
      parseInt(startParts[0]),
      parseInt(startParts[1]) - 1,
      parseInt(startParts[2])
    );
    start.setHours(0, 0, 0, 0);
    
    const end = new Date(
      parseInt(endParts[0]),
      parseInt(endParts[1]) - 1,
      parseInt(endParts[2])
    );
    end.setHours(23, 59, 59, 999);

    // Gerar ID único
    const id = `period_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    const periodData = {
      id,
      userId: req.userId,
      startDate: start,
      endDate: end,
      transactionIds: transactionIds || [],
      name: name || '',
    };

    const period = new PeriodHistory(periodData);
    await period.save();
    
    res.status(201).json(period);
  } catch (error) {
    if (error.code === 11000) {
      res.status(400).json({ message: 'Período com este ID já existe' });
    } else {
      res.status(500).json({ message: error.message });
    }
  }
});

// PUT atualizar história de período
router.put('/:id', validatePeriodId, async (req, res) => {
  try {
    const PeriodHistory = getPeriodHistoryModel(req.userId);
    const { name } = req.body;
    
    const period = await PeriodHistory.findOne({ 
      id: req.params.id,
      userId: req.userId 
    });
    
    if (!period) {
      return res.status(404).json({ message: 'Período não encontrado' });
    }
    
    // Atualizar apenas o nome se fornecido
    if (name !== undefined) {
      period.name = name || '';
    }
    
    await period.save();
    
    res.json(period);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// DELETE deletar história de período
router.delete('/:id', validatePeriodId, async (req, res) => {
  try {
    const PeriodHistory = getPeriodHistoryModel(req.userId);
    const { getTransactionModel } = require('../models/Transaction');
    const Transaction = getTransactionModel(req.userId);
    
    const period = await PeriodHistory.findOne({ 
      id: req.params.id,
      userId: req.userId 
    });
    
    if (!period) {
      return res.status(404).json({ message: 'Período não encontrado' });
    }
    
    // Eliminar transações únicas do período
    const startDate = new Date(period.startDate);
    startDate.setHours(0, 0, 0, 0);
    const endDate = new Date(period.endDate);
    endDate.setHours(23, 59, 59, 999);

    // Buscar todas as transações únicas no período
    const uniqueTransactions = await Transaction.find({
      userId: req.userId,
      frequency: 'unique',
      date: {
        $gte: startDate,
        $lte: endDate
      }
    });

    // Eliminar as transações únicas
    if (uniqueTransactions.length > 0) {
      const transactionIds = uniqueTransactions.map(t => t.id);
      await Transaction.deleteMany({
        userId: req.userId,
        id: { $in: transactionIds }
      });
    }

    // Eliminar o período
    await PeriodHistory.findOneAndDelete({ 
      id: req.params.id,
      userId: req.userId 
    });
    
    res.json({ 
      message: 'Período deletado com sucesso',
      deletedTransactions: uniqueTransactions.length
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

module.exports = router;
