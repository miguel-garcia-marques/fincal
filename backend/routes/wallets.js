const express = require('express');
const router = express.Router();
const { getWalletModel } = require('../models/Wallet');
const { getWalletMemberModel } = require('../models/WalletMember');
const { authenticateUser } = require('../middleware/auth');
const { checkWalletAccess, checkOwnerPermission } = require('../middleware/walletAuth');

// Aplicar middleware de autenticação em todas as rotas
router.use(authenticateUser);

// GET todas as wallets do usuário (próprias e das quais é membro)
router.get('/', async (req, res) => {
  try {
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();
    const { getUserModel } = require('../models/User');

    const User = getUserModel();
    const user = await User.findOne({ userId: req.userId });
    
    // CRÍTICO: Garantir que apenas UMA wallet pessoal seja retornada
    // Buscar wallet pessoal - priorizar personalWalletId do usuário
    let personalWallet = null;
    
    if (user && user.personalWalletId) {
      personalWallet = await Wallet.findById(user.personalWalletId);
      // Verificar se a wallet existe e pertence ao usuário
      if (personalWallet && personalWallet.ownerId === req.userId) {
        // Wallet pessoal encontrada pelo personalWalletId
      } else {
        // Se não existe ou não pertence, limpar personalWalletId
        personalWallet = null;
        if (user) {
          user.personalWalletId = null;
          await user.save();
        }
      }
    }
    
    // Se não encontrou pelo personalWalletId, buscar por ownerId
    // IMPORTANTE: Usar findOne para pegar apenas UMA wallet (a mais antiga)
    if (!personalWallet) {
      personalWallet = await Wallet.findOne({ ownerId: req.userId }).sort({ createdAt: 1 });
      
      // Se encontrou uma wallet pessoal, atualizar personalWalletId do usuário
      if (personalWallet && user) {
        user.personalWalletId = personalWallet._id;
        await user.save();
        console.log(`✅ personalWalletId atualizado para usuário ${req.userId}: ${personalWallet._id}`);
      }
    }
    
    // Se houver múltiplas wallets com mesmo ownerId, logar aviso
    const allOwnedWallets = await Wallet.find({ ownerId: req.userId });
    if (allOwnedWallets.length > 1) {
      console.warn(`⚠️  ATENÇÃO: Usuário ${req.userId} tem ${allOwnedWallets.length} wallets pessoais! Usando apenas a primeira: ${personalWallet?._id}`);
      console.warn(`   Todas as wallets: ${allOwnedWallets.map(w => w._id).join(', ')}`);
    }

    // Buscar wallets das quais é membro (não próprias)
    const memberShips = await WalletMember.find({ userId: req.userId });
    const memberWalletIds = memberShips.map(m => m.walletId);
    const memberWallets = await Wallet.find({ _id: { $in: memberWalletIds } });

    // Combinar e adicionar informações de permissão
    const wallets = [];
    
    // Adicionar APENAS a wallet pessoal principal (não todas as duplicadas)
    if (personalWallet) {
      const owner = await User.findOne({ userId: personalWallet.ownerId });
      wallets.push({
        ...personalWallet.toObject(),
        permission: 'owner',
        isOwner: true,
        ownerName: owner?.name || null
      });
    }

    // Adicionar wallets das quais é membro (não próprias)
    for (const wallet of memberWallets) {
      // Não adicionar se for wallet pessoal (já adicionada acima)
      if (wallet.ownerId !== req.userId) {
        const membership = memberShips.find(m => m.walletId.toString() === wallet._id.toString());
        // Buscar nome do owner
        const owner = await User.findOne({ userId: wallet.ownerId });
        wallets.push({
          ...wallet.toObject(),
          permission: membership?.permission || 'read',
          isOwner: false,
          ownerName: owner?.name || null
        });
      }
    }

    res.json(wallets);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// GET wallet específica
router.get('/:walletId', checkWalletAccess, async (req, res) => {
  try {
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();

    const wallet = await Wallet.findById(req.walletId);
    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    // Buscar membros da wallet
    const members = await WalletMember.find({ walletId: req.walletId }).populate('walletId');
    
    // Buscar informações dos usuários (se necessário)
    const walletData = {
      ...wallet.toObject(),
      permission: req.walletPermission,
      isOwner: wallet.ownerId === req.userId,
      members: members.map(m => ({
        userId: m.userId,
        permission: m.permission,
        joinedAt: m.joinedAt
      }))
    };

    res.json(walletData);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar nova wallet
router.post('/', async (req, res) => {
  try {
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();
    const { getUserModel } = require('../models/User');

    const { name } = req.body;
    const walletName = name || 'Minha Carteira Calendário';

    // Verificar se o usuário já tem uma wallet pessoal
    const User = getUserModel();
    const user = await User.findOne({ userId: req.userId });
    
    // Se o usuário já tem uma personalWalletId, retornar essa wallet
    if (user && user.personalWalletId) {
      const existingWallet = await Wallet.findById(user.personalWalletId);
      if (existingWallet) {
        // Verificar se é realmente do usuário (segurança)
        if (existingWallet.ownerId === req.userId) {
          return res.status(200).json({
            ...existingWallet.toObject(),
            permission: 'owner',
            isOwner: true
          });
        }
      }
    }

    // Verificar se já existe alguma wallet com este ownerId
    const existingOwnedWallet = await Wallet.findOne({ ownerId: req.userId });
    if (existingOwnedWallet) {
      // Se o usuário não tinha personalWalletId, atualizar
      if (user && !user.personalWalletId) {
        user.personalWalletId = existingOwnedWallet._id;
        await user.save();
      }
      
      return res.status(200).json({
        ...existingOwnedWallet.toObject(),
        permission: 'owner',
        isOwner: true
      });
    }

    // Criar wallet apenas se não existir nenhuma
    const wallet = new Wallet({
      name: walletName,
      ownerId: req.userId
    });
    await wallet.save();

    // Criar membership do dono
    const ownerMember = new WalletMember({
      walletId: wallet._id,
      userId: req.userId,
      permission: 'owner'
    });
    await ownerMember.save();

    // Atualizar personalWalletId do usuário se existir
    if (user) {
      user.personalWalletId = wallet._id;
      await user.save();
    }

    res.status(201).json({
      ...wallet.toObject(),
      permission: 'owner',
      isOwner: true
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// PUT atualizar wallet (apenas dono)
router.put('/:walletId', checkWalletAccess, checkOwnerPermission, async (req, res) => {
  try {
    const Wallet = getWalletModel();
    const { name } = req.body;

    const wallet = await Wallet.findByIdAndUpdate(
      req.walletId,
      { name, updatedAt: new Date() },
      { new: true, runValidators: true }
    );

    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    res.json({
      ...wallet.toObject(),
      permission: 'owner',
      isOwner: true
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// DELETE wallet (apenas dono)
router.delete('/:walletId', checkWalletAccess, checkOwnerPermission, async (req, res) => {
  try {
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();
    const { getTransactionModel } = require('../models/Transaction');

    // Verificar se a wallet existe
    const wallet = await Wallet.findById(req.walletId);
    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    // Deletar todas as transações da wallet
    const Transaction = getTransactionModel();
    await Transaction.deleteMany({ walletId: req.walletId });

    // Deletar todos os membros
    await WalletMember.deleteMany({ walletId: req.walletId });

    // Deletar todos os convites pendentes
    const { getInviteModel } = require('../models/Invite');
    const Invite = getInviteModel();
    await Invite.deleteMany({ walletId: req.walletId });

    // Deletar a wallet
    await Wallet.findByIdAndDelete(req.walletId);

    res.json({ message: 'Wallet deletada com sucesso' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// GET membros da wallet
router.get('/:walletId/members', checkWalletAccess, async (req, res) => {
  try {
    const WalletMember = getWalletMemberModel();
    const { getUserModel } = require('../models/User');

    const members = await WalletMember.find({ walletId: req.walletId });
    
    // Buscar informações dos usuários
    const User = getUserModel();
    const membersWithInfo = await Promise.all(
      members.map(async (member) => {
        const user = await User.findOne({ userId: member.userId });
        return {
          userId: member.userId,
          email: user?.email || null,
          name: user?.name || null,
          permission: member.permission,
          joinedAt: member.joinedAt,
          isOwner: false // Será atualizado abaixo se necessário
        };
      })
    );

    // Adicionar informação do dono
    const Wallet = getWalletModel();
    const wallet = await Wallet.findById(req.walletId);
    if (wallet) {
      const owner = await User.findOne({ userId: wallet.ownerId });
      const ownerIndex = membersWithInfo.findIndex(m => m.userId === wallet.ownerId);
      if (ownerIndex >= 0) {
        membersWithInfo[ownerIndex].isOwner = true;
        membersWithInfo[ownerIndex].permission = 'owner';
      } else {
        membersWithInfo.unshift({
          userId: wallet.ownerId,
          email: owner?.email || null,
          name: owner?.name || null,
          permission: 'owner',
          joinedAt: wallet.createdAt,
          isOwner: true
        });
      }
    }

    res.json(membersWithInfo);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// DELETE remover membro (apenas dono)
router.delete('/:walletId/members/:userId', checkWalletAccess, checkOwnerPermission, async (req, res) => {
  try {
    const WalletMember = getWalletMemberModel();
    const Wallet = getWalletModel();

    const wallet = await Wallet.findById(req.walletId);
    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    // Não permitir remover o dono
    if (wallet.ownerId === req.params.userId) {
      return res.status(400).json({ message: 'Não é possível remover o dono da wallet' });
    }

    const member = await WalletMember.findOneAndDelete({
      walletId: req.walletId,
      userId: req.params.userId
    });

    if (!member) {
      return res.status(404).json({ message: 'Membro não encontrado' });
    }

    res.json({ message: 'Membro removido com sucesso' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// PUT atualizar permissão de membro (apenas dono)
router.put('/:walletId/members/:userId', checkWalletAccess, checkOwnerPermission, async (req, res) => {
  try {
    const WalletMember = getWalletMemberModel();
    const { permission } = req.body;

    if (!permission || !['read', 'write'].includes(permission)) {
      return res.status(400).json({ message: 'Permissão inválida. Use "read" ou "write"' });
    }

    const member = await WalletMember.findOneAndUpdate(
      { walletId: req.walletId, userId: req.params.userId },
      { permission },
      { new: true, runValidators: true }
    );

    if (!member) {
      return res.status(404).json({ message: 'Membro não encontrado' });
    }

    res.json(member);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

module.exports = router;

