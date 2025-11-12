const express = require('express');
const router = express.Router();
const { getUserModel } = require('../models/User');
const { authenticateUser } = require('../middleware/auth');
const { validateUser } = require('../middleware/validation');

// Aplicar middleware de autenticação em todas as rotas
router.use(authenticateUser);

// Helper para garantir que o usuário tenha uma wallet pessoal
async function ensurePersonalWallet(userId) {
  const { getWalletModel } = require('../models/Wallet');
  const { getWalletMemberModel } = require('../models/WalletMember');
  const Wallet = getWalletModel();
  const WalletMember = getWalletMemberModel();
  const User = getUserModel();
  
  // Buscar usuário para verificar personalWalletId
  const user = await User.findOne({ userId: userId });
  
  let personalWallet = null;
  
  // Se o usuário tem personalWalletId, tentar usar essa wallet
  if (user && user.personalWalletId) {
    personalWallet = await Wallet.findById(user.personalWalletId);
    // Verificar se a wallet existe e pertence ao usuário
    if (personalWallet && personalWallet.ownerId === userId) {
      return personalWallet;
    }
    // Se a wallet não existe ou não pertence ao usuário, limpar personalWalletId
    if (user) {
      user.personalWalletId = null;
      await user.save();
    }
  }
  
  // Se não encontrou pelo personalWalletId, buscar por ownerId
  // Usar findOne para pegar apenas uma (a mais antiga se houver múltiplas)
  personalWallet = await Wallet.findOne({ ownerId: userId }).sort({ createdAt: 1 });
  
  if (personalWallet) {
    // Atualizar personalWalletId do usuário se não estiver definido
    if (user && !user.personalWalletId) {
      user.personalWalletId = personalWallet._id;
      await user.save();
    }
    return personalWallet;
  }
  
  // Criar wallet pessoal apenas se não existir nenhuma
  personalWallet = new Wallet({
    name: 'Minha Carteira Calendário',
    ownerId: userId,
  });
  await personalWallet.save();
  
  // Criar membership do dono
  const ownerMember = new WalletMember({
    walletId: personalWallet._id,
    userId: userId,
    permission: 'owner'
  });
  await ownerMember.save();
  
  // Atualizar personalWalletId do usuário
  if (user) {
    try {
      user.personalWalletId = personalWallet._id;
      await user.save();
    } catch (error) {
      // Se falhar ao salvar, tentar novamente após um pequeno delay
      // Isso pode acontecer em casos de concorrência
      try {
        await new Promise(resolve => setTimeout(resolve, 100));
        const retryUser = await User.findOne({ userId: userId });
        if (retryUser) {
          retryUser.personalWalletId = personalWallet._id;
          await retryUser.save();
        }
      } catch (retryError) {
        // Se ainda falhar, continuar - a wallet foi criada e pode ser vinculada depois
      }
    }
  }
  // Se o usuário não existe ainda, será criado depois quando o usuário fizer POST /users
  
  return personalWallet;
}

// GET obter dados do usuário atual
router.get('/me', async (req, res) => {
  try {
    const User = getUserModel();
    let user = await User.findOne({ userId: req.userId });
    
    if (!user) {
      return res.status(404).json({ message: 'Usuário não encontrado' });
    }
    
    // Garantir que o usuário tem uma wallet pessoal (para usuários antigos)
    try {
      const personalWallet = await ensurePersonalWallet(req.userId);
      
      // Se não tiver personalWalletId, atualizar
      if (!user.personalWalletId) {
        user.personalWalletId = personalWallet._id;
        if (!user.walletsInvited) {
          user.walletsInvited = [];
        }
        try {
          await user.save();
        } catch (saveError) {
          // Se falhar ao salvar, tentar novamente após um delay
          await new Promise(resolve => setTimeout(resolve, 100));
          user = await User.findOne({ userId: req.userId });
          if (user && !user.personalWalletId) {
            user.personalWalletId = personalWallet._id;
            if (!user.walletsInvited) {
              user.walletsInvited = [];
            }
            await user.save();
          }
        }
      } else {
        // Verificar se a wallet referenciada ainda existe e pertence ao usuário
        const { getWalletModel } = require('../models/Wallet');
        const Wallet = getWalletModel();
        const referencedWallet = await Wallet.findById(user.personalWalletId);
        if (!referencedWallet || referencedWallet.ownerId !== req.userId) {
          // Wallet não existe ou não pertence ao usuário, atualizar
          user.personalWalletId = personalWallet._id;
          if (!user.walletsInvited) {
            user.walletsInvited = [];
          }
          await user.save();
        } else {
          // Garantir que walletsInvited existe
          if (!user.walletsInvited) {
            user.walletsInvited = [];
            await user.save();
          }
        }
      }
    } catch (walletError) {
      // Se falhar ao garantir wallet, continuar mesmo assim
      // O usuário será retornado e a wallet será criada na próxima tentativa
      if (!user.walletsInvited) {
        user.walletsInvited = [];
        try {
          await user.save();
        } catch (saveError) {
          // Ignorar erro ao salvar
        }
      }
    }
    
    // Recarregar usuário para garantir que temos os dados mais recentes
    user = await User.findOne({ userId: req.userId });
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar ou atualizar usuário
router.post('/', validateUser, async (req, res) => {
  try {
    const User = getUserModel();
    const { getWalletModel } = require('../models/Wallet');
    const { getWalletMemberModel } = require('../models/WalletMember');
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();
    const { name } = req.body;
    
    if (!name || name.trim().length === 0) {
      return res.status(400).json({ message: 'Nome é obrigatório' });
    }
    
    // Buscar usuário existente
    let user = await User.findOne({ userId: req.userId });
    let isNewUser = false;
    
    if (user) {
      // Atualizar usuário existente
      user.name = name.trim();
      user.email = req.user.email || user.email;
      user.updatedAt = new Date();
      
      // Se não tiver personalWalletId, garantir que tenha uma wallet pessoal
      if (!user.personalWalletId) {
        try {
          const personalWallet = await ensurePersonalWallet(req.userId);
          user.personalWalletId = personalWallet._id;
        } catch (walletError) {
          // Se falhar ao criar wallet, tentar buscar uma existente
          const { getWalletModel } = require('../models/Wallet');
          const Wallet = getWalletModel();
          const existingWallet = await Wallet.findOne({ ownerId: req.userId }).sort({ createdAt: 1 });
          if (existingWallet) {
            user.personalWalletId = existingWallet._id;
          }
          // Se não encontrar wallet existente, continuar sem personalWalletId
          // Será criada na próxima tentativa
        }
      } else {
        // Verificar se a wallet referenciada ainda existe e pertence ao usuário
        const { getWalletModel } = require('../models/Wallet');
        const Wallet = getWalletModel();
        const referencedWallet = await Wallet.findById(user.personalWalletId);
        if (!referencedWallet || referencedWallet.ownerId !== req.userId) {
          // Wallet não existe ou não pertence ao usuário, criar nova
          try {
            const personalWallet = await ensurePersonalWallet(req.userId);
            user.personalWalletId = personalWallet._id;
          } catch (walletError) {
            // Se falhar, limpar personalWalletId - será criada depois
            user.personalWalletId = null;
          }
        }
      }
      
      // Garantir que walletsInvited existe
      if (!user.walletsInvited) {
        user.walletsInvited = [];
      }
      
      await user.save();
    } else {
      // Criar novo usuário
      isNewUser = true;
      
      // Criar wallet pessoal automaticamente para novos usuários
      const personalWallet = await ensurePersonalWallet(req.userId);
      
      user = new User({
        userId: req.userId,
        email: req.user.email,
        name: name.trim(),
        personalWalletId: personalWallet._id,
        walletsInvited: []
      });
      await user.save();
      
      console.log(`✅ Wallet pessoal criada para novo usuário ${req.userId}: ${personalWallet._id}`);
    }
    
    res.status(201).json(user);
  } catch (error) {
    if (error.code === 11000) {
      res.status(400).json({ message: 'Usuário já existe' });
    } else {
      res.status(500).json({ message: error.message });
    }
  }
});

// PUT atualizar nome do usuário
router.put('/me', validateUser, async (req, res) => {
  try {
    const User = getUserModel();
    const { name } = req.body;
    
    if (!name || name.trim().length === 0) {
      return res.status(400).json({ message: 'Nome é obrigatório' });
    }
    
    const user = await User.findOneAndUpdate(
      { userId: req.userId },
      { 
        name: name.trim(),
        email: req.user.email,
        updatedAt: new Date()
      },
      { new: true, upsert: true }
    );
    
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

module.exports = router;

