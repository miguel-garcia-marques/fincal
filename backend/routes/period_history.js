const express = require('express');
const router = express.Router();
const { getPeriodHistoryModel } = require('../models/PeriodHistory');
const { authenticateUser } = require('../middleware/auth');
const { validatePeriodHistory, validatePeriodId } = require('../middleware/validation');

// Aplicar middleware de autenticação em todas as rotas
router.use(authenticateUser);

// GET todas as histórias de períodos do usuário
// Aceita parâmetro opcional ownerId para buscar períodos do dono de uma wallet compartilhada
router.get('/', async (req, res) => {
  try {
    const { ownerId } = req.query;
    let targetUserId = req.userId;
    
    // Se ownerId foi fornecido, verificar se o usuário tem acesso a uma wallet desse owner
    if (ownerId && ownerId !== req.userId) {
      const { getWalletModel } = require('../models/Wallet');
      const { getWalletMemberModel } = require('../models/WalletMember');
      const Wallet = getWalletModel();
      const WalletMember = getWalletMemberModel();
      
      // Verificar se o usuário tem acesso a uma wallet desse owner
      const wallet = await Wallet.findOne({ ownerId: ownerId });
      if (wallet) {
        // Verificar se o usuário é membro dessa wallet ou é o owner
        const membership = await WalletMember.findOne({
          walletId: wallet._id,
          userId: req.userId
        });
        
        // Se não for membro e não for o owner, retornar erro
        if (!membership && wallet.ownerId !== req.userId) {
          return res.status(403).json({ 
            message: 'Você não tem permissão para acessar os períodos deste usuário' 
          });
        }
        
        // Usar ownerId como targetUserId
        targetUserId = ownerId;
      } else {
        return res.status(404).json({ 
          message: 'Wallet não encontrada para este owner' 
        });
      }
    }
    
    const PeriodHistory = getPeriodHistoryModel(targetUserId);
    const periods = await PeriodHistory.find({ userId: targetUserId })
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
// Aceita parâmetro opcional ownerId para criar período para o dono de uma wallet compartilhada
router.post('/', validatePeriodHistory, async (req, res) => {
  try {
    const { startDate, endDate, transactionIds, name, ownerId } = req.body;
    
    if (!startDate || !endDate) {
      return res.status(400).json({ 
        message: 'startDate e endDate são obrigatórios' 
      });
    }

    let targetUserId = req.userId;
    
    // Se ownerId foi fornecido e é diferente do usuário logado, verificar permissão
    if (ownerId && ownerId !== req.userId) {
      const { getWalletModel } = require('../models/Wallet');
      const { getWalletMemberModel } = require('../models/WalletMember');
      const Wallet = getWalletModel();
      const WalletMember = getWalletMemberModel();
      
      // Verificar se o usuário tem acesso a uma wallet desse owner
      const wallet = await Wallet.findOne({ ownerId: ownerId });
      if (wallet) {
        // Verificar se o usuário é membro dessa wallet com permissão de escrita
        const membership = await WalletMember.findOne({
          walletId: wallet._id,
          userId: req.userId
        });
        
        // Se não for membro com permissão de escrita e não for o owner, retornar erro
        if (!membership || (membership.permission !== 'write' && membership.permission !== 'owner')) {
          return res.status(403).json({ 
            message: 'Você não tem permissão para criar períodos nesta wallet' 
          });
        }
        
        // Usar ownerId como targetUserId
        targetUserId = ownerId;
      } else {
        return res.status(404).json({ 
          message: 'Wallet não encontrada para este owner' 
        });
      }
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

    const PeriodHistory = getPeriodHistoryModel(targetUserId);
    const periodData = {
      id,
      userId: targetUserId,
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
// Aceita parâmetro opcional ownerId para deletar período do dono de uma wallet compartilhada
router.delete('/:id', validatePeriodId, async (req, res) => {
  try {
    const { ownerId } = req.query;
    let targetUserId = req.userId;
    
    // Se ownerId foi fornecido e é diferente do usuário logado, verificar permissão
    if (ownerId && ownerId !== req.userId) {
      const { getWalletModel } = require('../models/Wallet');
      const { getWalletMemberModel } = require('../models/WalletMember');
      const Wallet = getWalletModel();
      const WalletMember = getWalletMemberModel();
      
      // Verificar se o usuário tem acesso a uma wallet desse owner
      const wallet = await Wallet.findOne({ ownerId: ownerId });
      if (wallet) {
        // Verificar se o usuário é membro dessa wallet com permissão de escrita
        const membership = await WalletMember.findOne({
          walletId: wallet._id,
          userId: req.userId
        });
        
        // Se não for membro com permissão de escrita e não for o owner, retornar erro
        if (!membership || (membership.permission !== 'write' && membership.permission !== 'owner')) {
          return res.status(403).json({ 
            message: 'Você não tem permissão para deletar períodos nesta wallet' 
          });
        }
        
        // Usar ownerId como targetUserId
        targetUserId = ownerId;
      } else {
        return res.status(404).json({ 
          message: 'Wallet não encontrada para este owner' 
        });
      }
    }
    
    const PeriodHistory = getPeriodHistoryModel(targetUserId);
    const { getTransactionModel } = require('../models/Transaction');
    const Transaction = getTransactionModel(targetUserId);
    
    const period = await PeriodHistory.findOne({ 
      id: req.params.id,
      userId: targetUserId 
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
      userId: targetUserId,
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
        userId: targetUserId,
        id: { $in: transactionIds }
      });
    }

    // Eliminar o período
    await PeriodHistory.findOneAndDelete({ 
      id: req.params.id,
      userId: targetUserId 
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
