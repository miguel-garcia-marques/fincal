const express = require('express');
const router = express.Router();
const { getUserModel } = require('../models/User');
const { authenticateUser } = require('../middleware/auth');
const { validateUser, validateUserUpdate } = require('../middleware/validation');

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
    
    // Se o usuário não existir, criar automaticamente
    if (!user) {
      // Criar wallet pessoal primeiro
      const personalWallet = await ensurePersonalWallet(req.userId);
      
      // Criar novo usuário com dados básicos do Supabase
      // Buscar display_name do Supabase (que é onde salvamos o nome)
      const displayName = req.user.user_metadata?.display_name || req.user.user_metadata?.name;
      user = new User({
        userId: req.userId,
        email: req.user.email || null,
        name: displayName || req.user.email?.split('@')[0] || 'Usuário',
        personalWalletId: personalWallet._id,
        walletsInvited: []
      });
      await user.save();
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
    
    // Sincronizar nome do Supabase se disponível e diferente do MongoDB
    const displayName = req.user.user_metadata?.display_name || req.user.user_metadata?.name;
    if (displayName && user.name !== displayName) {
      // Se o nome do Supabase estiver disponível e for diferente, atualizar no MongoDB
      user.name = displayName;
      await user.save();
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

// PUT atualizar nome do usuário ou foto de perfil
router.put('/me', validateUserUpdate, async (req, res) => {
  try {
    const User = getUserModel();
    const { name, profilePictureUrl } = req.body;
    
    console.log(`[PUT /users/me] Atualizando perfil para userId: ${req.userId}`);
    console.log(`[PUT /users/me] Dados recebidos:`, { name, profilePictureUrl });
    
    // Construir objeto de atualização dinamicamente
    const updateData = {
      updatedAt: new Date()
    };
    
    if (name !== undefined) {
      if (!name || name.trim().length === 0) {
        return res.status(400).json({ message: 'Nome é obrigatório' });
      }
      updateData.name = name.trim();
      console.log(`[PUT /users/me] Atualizando nome: ${updateData.name}`);
    }
    
    if (profilePictureUrl !== undefined) {
      // Converter string vazia para null
      const finalProfilePictureUrl = (profilePictureUrl && profilePictureUrl.trim() !== '') 
        ? profilePictureUrl.trim() 
        : null;
      updateData.profilePictureUrl = finalProfilePictureUrl;
      console.log(`[PUT /users/me] Atualizando profilePictureUrl: ${finalProfilePictureUrl}`);
    }
    
    // Sempre atualizar email se disponível
    if (req.user.email) {
      updateData.email = req.user.email;
    }
    
    console.log(`[PUT /users/me] Dados de atualização:`, updateData);
    
    const user = await User.findOneAndUpdate(
      { userId: req.userId },
      updateData,
      { new: true, upsert: true }
    );
    
    console.log(`[PUT /users/me] Usuário atualizado:`, {
      userId: user.userId,
      name: user.name,
      profilePictureUrl: user.profilePictureUrl
    });
    
    res.json(user);
  } catch (error) {
    console.error(`[PUT /users/me] Erro ao atualizar perfil:`, error);
    res.status(500).json({ message: error.message });
  }
});

// DELETE deletar conta do usuário e todos os dados associados
router.delete('/me', async (req, res) => {
  try {
    const User = getUserModel();
    const { getWalletModel } = require('../models/Wallet');
    const { getWalletMemberModel } = require('../models/WalletMember');
    const { getTransactionModel } = require('../models/Transaction');
    const { getPeriodHistoryModel } = require('../models/PeriodHistory');
    const { getInviteModel } = require('../models/Invite');
    const { createClient } = require('@supabase/supabase-js');
    
    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();
    const Invite = getInviteModel();
    
    const userId = req.userId;
    const userEmail = req.user.email;
    
    // Criar cliente Supabase Admin para deletar usuário
    const supabaseAdmin = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    );
    
    // 1. Buscar o usuário para obter informações
    const user = await User.findOne({ userId: userId });
    
    if (!user) {
      return res.status(404).json({ message: 'Usuário não encontrado' });
    }
    
    // 2. Buscar todas as wallets onde o usuário é owner
    const ownedWallets = await Wallet.find({ ownerId: userId });
    const walletIds = ownedWallets.map(w => w._id);
    
    // 3. Buscar todas as wallet members do usuário
    const walletMembers = await WalletMember.find({ userId: userId });
    const allWalletIds = [...new Set([...walletIds, ...walletMembers.map(wm => wm.walletId)])];
    
    // 4. Deletar todas as transações de todas as wallets do usuário
    for (const walletId of allWalletIds) {
      try {
        const Transaction = getTransactionModel(walletId);
        // Deletar apenas transações criadas pelo usuário ou associadas ao userId
        await Transaction.deleteMany({ 
          $or: [
            { userId: userId },
            { createdBy: userId }
          ]
        });
        
        // Também deletar a collection se estiver vazia (opcional)
        const remainingTransactions = await Transaction.countDocuments({ walletId: walletId });
        if (remainingTransactions === 0) {
          try {
            await Transaction.collection.drop();
          } catch (dropError) {
            // Ignorar erro se a collection não existir ou não puder ser deletada
          }
        }
      } catch (txError) {
        // Continuar mesmo se houver erro ao deletar transações de uma wallet
        console.error(`Erro ao deletar transações da wallet ${walletId}:`, txError);
      }
    }
    
    // 5. Deletar todas as period histories do usuário
    try {
      const PeriodHistory = getPeriodHistoryModel(userId);
      await PeriodHistory.deleteMany({ userId: userId });
      
      // Tentar deletar a collection se estiver vazia
      try {
        await PeriodHistory.collection.drop();
      } catch (dropError) {
        // Ignorar erro se a collection não existir
      }
    } catch (phError) {
      console.error('Erro ao deletar period history:', phError);
    }
    
    // 6. Deletar todos os invites criados pelo usuário ou para o usuário
    await Invite.deleteMany({
      $or: [
        { invitedBy: userId },
        { email: userEmail },
        { acceptedBy: userId }
      ]
    });
    
    // 7. Deletar todas as wallet members do usuário
    await WalletMember.deleteMany({ userId: userId });
    
    // 8. Para wallets onde o usuário é owner, deletar todos os wallet members e depois a wallet
    for (const wallet of ownedWallets) {
      // Deletar todos os members desta wallet
      await WalletMember.deleteMany({ walletId: wallet._id });
      // Deletar a wallet
      await Wallet.deleteOne({ _id: wallet._id });
    }
    
    // 9. Remover referências do usuário em outras wallets (se houver)
    // Atualizar walletsInvited de outros usuários que podem ter referências
    const allUsers = await User.find({ walletsInvited: { $in: walletIds } });
    for (const otherUser of allUsers) {
      if (otherUser.walletsInvited) {
        otherUser.walletsInvited = otherUser.walletsInvited.filter(
          wid => !walletIds.some(wid2 => wid2.toString() === wid.toString())
        );
        await otherUser.save();
      }
    }
    
    // 10. Deletar o usuário do MongoDB
    await User.deleteOne({ userId: userId });
    
    // 11. Deletar usuário do Supabase Auth usando Admin API
    try {
      const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(userId);
      if (deleteError) {
        console.error('Erro ao deletar usuário do Supabase Auth:', deleteError);
        // Continuar mesmo se falhar - os dados do MongoDB já foram deletados
      }
    } catch (supabaseError) {
      console.error('Erro ao deletar usuário do Supabase Auth:', supabaseError);
      // Continuar mesmo se falhar - os dados do MongoDB já foram deletados
    }
    
    // 12. Retornar sucesso
    res.json({ 
      message: 'Conta e todos os dados associados foram deletados com sucesso',
      deleted: {
        user: true,
        wallets: ownedWallets.length,
        walletMembers: walletMembers.length,
        transactions: 'all',
        periodHistories: true,
        invites: true,
        supabaseAuth: true
      }
    });
  } catch (error) {
    console.error('Erro ao deletar conta:', error);
    res.status(500).json({ message: 'Erro ao deletar conta: ' + error.message });
  }
});

module.exports = router;
