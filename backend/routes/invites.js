const express = require('express');
const router = express.Router();
const { getInviteModel } = require('../models/Invite');
const { getWalletModel } = require('../models/Wallet');
const { getWalletMemberModel } = require('../models/WalletMember');
const { getUserModel } = require('../models/User');
const { authenticateUser } = require('../middleware/auth');
const { checkWalletAccess, checkOwnerPermission } = require('../middleware/walletAuth');

// Garantir que os modelos estão registrados no início
// Isso é necessário para que o populate funcione corretamente
getWalletModel();
getInviteModel();
getWalletMemberModel();
getUserModel();

// Helper para converter invite para JSON com datas formatadas
async function inviteToJson(invite, invitedByName = null) {
  // Se não tiver o nome do usuário e tiver o ID, buscar
  if (!invitedByName && invite.invitedBy) {
    try {
      const User = getUserModel();
      const user = await User.findOne({ userId: invite.invitedBy });
      if (user) {
        invitedByName = user.name;
      }
    } catch (error) {
      console.warn(`Warning: Could not fetch user name for invitedBy ${invite.invitedBy}: ${error.message}`);
    }
  }

  // Buscar nome do usuário que aceitou, se houver
  let acceptedByName = null;
  if (invite.acceptedBy) {
    try {
      const User = getUserModel();
      const user = await User.findOne({ userId: invite.acceptedBy });
      if (user) {
        acceptedByName = user.name;
      }
    } catch (error) {
      console.warn(`Warning: Could not fetch user name for acceptedBy ${invite.acceptedBy}: ${error.message}`);
    }
  }

  // Converter para objeto plano, garantindo que timestamps sejam incluídos
  let json;
  if (invite.toObject) {
    json = invite.toObject({ 
      virtuals: false,
      getters: true,
      flattenObjectIds: false
    });
  } else {
    json = invite;
  }
  
  // Acessar campos diretamente do documento Mongoose se necessário
  // (os timestamps podem não estar no toObject em alguns casos)
  const expiresAt = json.expiresAt || invite.expiresAt;
  const createdAt = json.createdAt || invite.createdAt;
  const acceptedAt = json.acceptedAt || invite.acceptedAt;
  
  // Helper para converter data para string ISO (nunca retorna null para campos obrigatórios)
  const formatDate = (dateValue, required = false) => {
    // Se for null, undefined, ou string vazia
    if (dateValue === null || dateValue === undefined || dateValue === '') {
      if (required) {
        // Se for obrigatório e não existir, usar data atual
        console.warn(`Warning: Required date field is null, using current date as fallback`);
        return new Date().toISOString();
      }
      return null;
    }
    
    // Se já é uma instância de Date
    if (dateValue instanceof Date) {
      // Verificar se é uma data válida
      if (isNaN(dateValue.getTime())) {
        console.warn(`Warning: Invalid Date object, using current date as fallback`);
        return required ? new Date().toISOString() : null;
      }
      return dateValue.toISOString();
    }
    
    // Se é string
    if (typeof dateValue === 'string') {
      if (dateValue.trim() === '' || dateValue === 'null' || dateValue === 'undefined') {
        return required ? new Date().toISOString() : null;
      }
      try {
        const parsed = new Date(dateValue);
        if (isNaN(parsed.getTime())) {
          // Data inválida
          console.warn(`Warning: Invalid date string "${dateValue}", using current date as fallback`);
          return required ? new Date().toISOString() : null;
        }
        return parsed.toISOString();
      } catch (e) {
        console.warn(`Warning: Error parsing date string "${dateValue}": ${e.message}`);
        return required ? new Date().toISOString() : null;
      }
    }
    
    // Se é um objeto (pode ser um ObjectId ou outro formato)
    if (typeof dateValue === 'object' && dateValue !== null) {
      // Tentar extrair data de formatos especiais do Mongoose
      if (dateValue.$date) {
        return formatDate(dateValue.$date, required);
      }
      // Se não conseguir, usar fallback
      console.warn(`Warning: Unknown date object format: ${JSON.stringify(dateValue)}`);
      return required ? new Date().toISOString() : null;
    }
    
    // Fallback para qualquer outro tipo
    console.warn(`Warning: Unknown date type: ${typeof dateValue}, value: ${dateValue}`);
    return required ? new Date().toISOString() : null;
  };
  
  return {
    _id: json._id,
    walletId: json.walletId?._id || json.walletId,
    wallet: json.walletId && typeof json.walletId === 'object' && json.walletId._id ? {
      _id: json.walletId._id,
      name: json.walletId.name,
      ownerId: json.walletId.ownerId
    } : null,
    invitedBy: json.invitedBy || '',
    invitedByName: invitedByName || null,
    email: json.email || null,
    token: json.token || '',
    permission: json.permission || 'read',
    status: json.status || 'pending',
    expiresAt: formatDate(expiresAt, true), // Obrigatório - sempre retorna string ISO válida
    createdAt: formatDate(createdAt, true), // Obrigatório - sempre retorna string ISO válida
    acceptedAt: formatDate(acceptedAt, false), // Opcional - pode ser null
    acceptedBy: json.acceptedBy || null,
    acceptedByName: acceptedByName || null,
  };
}

// GET convite por token (público - permite visualizar sem autenticação)
// Esta rota deve vir ANTES do middleware de autenticação
router.get('/token/:token', async (req, res) => {
  try {
    // Garantir que os modelos estão registrados
    const Wallet = getWalletModel();
    const Invite = getInviteModel();
    const User = getUserModel();
    
    const invite = await Invite.findOne({ token: req.params.token })
      .populate('walletId');

    if (!invite) {
      return res.status(404).json({ message: 'Convite não encontrado' });
    }

    if (invite.isExpired()) {
      invite.status = 'expired';
      await invite.save();
      return res.status(400).json({ message: 'Convite expirado' });
    }

    // Retornar informações básicas do convite (sem dados sensíveis)
    const inviteJson = await inviteToJson(invite);
    // Não retornar email por segurança
    delete inviteJson.email;
    res.json(inviteJson);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// Aplicar middleware de autenticação nas rotas restantes
router.use(authenticateUser);

// GET todos os convites de uma wallet (apenas dono)
router.get('/wallet/:walletId', checkWalletAccess, checkOwnerPermission, async (req, res) => {
  try {
    const Invite = getInviteModel();
    const invites = await Invite.find({ walletId: req.walletId })
      .sort({ createdAt: -1 });

    const invitesJson = await Promise.all(invites.map(invite => inviteToJson(invite)));
    res.json(invitesJson);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// GET convites pendentes do usuário atual
router.get('/pending', async (req, res) => {
  try {
    // Garantir que os modelos estão registrados
    const Wallet = getWalletModel();
    const Invite = getInviteModel();
    const User = getUserModel();
    
    const user = await User.findOne({ userId: req.userId });
    if (!user) {
      return res.status(404).json({ message: 'Usuário não encontrado' });
    }

    const invites = await Invite.find({ 
      email: user.email,
      status: 'pending'
    })
      .populate('walletId')
      .sort({ createdAt: -1 });

    // Filtrar convites expirados
    const validInvites = invites.filter(invite => !invite.isExpired());

    const invitesJson = await Promise.all(validInvites.map(invite => inviteToJson(invite)));
    res.json(invitesJson);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar convite (apenas dono)
router.post('/', async (req, res) => {
  try {
    const { walletId, email, permission } = req.body;

    if (!walletId) {
      return res.status(400).json({ message: 'Wallet ID é obrigatório' });
    }

    if (!permission || !['read', 'write'].includes(permission)) {
      return res.status(400).json({ message: 'Permissão inválida. Use "read" ou "write"' });
    }

    // Verificar se o usuário é dono da wallet
    const Wallet = getWalletModel();
    const wallet = await Wallet.findById(walletId);
    
    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    if (wallet.ownerId !== req.userId) {
      return res.status(403).json({ message: 'Apenas o dono da wallet pode criar convites' });
    }

    const Invite = getInviteModel();
    const WalletMember = getWalletMemberModel();

    // Se email foi fornecido, verificar se já é membro
    if (email) {
      const User = getUserModel();
      const invitedUser = await User.findOne({ email });
      
      if (invitedUser) {
        const existingMember = await WalletMember.findOne({
          walletId: walletId,
          userId: invitedUser.userId
        });

        if (existingMember) {
          return res.status(400).json({ message: 'Este usuário já é membro da wallet' });
        }

        // Verificar se já existe convite pendente para este email
        const existingInvite = await Invite.findOne({
          walletId: walletId,
          email: email,
          status: 'pending'
        });

        if (existingInvite && !existingInvite.isExpired()) {
          return res.status(400).json({ message: 'Já existe um convite pendente para este email' });
        }
      }
    }

    // Criar convite
    const invite = new Invite({
      walletId: walletId,
      invitedBy: req.userId,
      email: email || null,
      permission: permission,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // 30 dias a partir de agora
    });
    await invite.save();

    // Recarregar o convite do banco para garantir que todos os campos estão populados (incluindo timestamps)
    const savedInvite = await Invite.findById(invite._id);
    
    if (!savedInvite) {
      return res.status(500).json({ message: 'Erro ao salvar convite' });
    }
    
    res.status(201).json(await inviteToJson(savedInvite));
  } catch (error) {
    if (error.code === 11000) {
      res.status(400).json({ message: 'Convite com este token já existe' });
    } else {
      res.status(500).json({ message: error.message });
    }
  }
});

// POST aceitar convite (requer autenticação)
router.post('/:token/accept', authenticateUser, async (req, res) => {
  try {
    // Garantir que os modelos estão registrados
    const Wallet = getWalletModel();
    const Invite = getInviteModel();
    const WalletMember = getWalletMemberModel();
    const User = getUserModel();

    const invite = await Invite.findOne({ token: req.params.token })
      .populate('walletId');

    if (!invite) {
      return res.status(404).json({ message: 'Convite não encontrado' });
    }

    if (invite.isExpired()) {
      invite.status = 'expired';
      await invite.save();
      return res.status(400).json({ message: 'Convite expirado' });
    }

    if (invite.status !== 'pending') {
      return res.status(400).json({ message: 'Convite já foi aceito ou expirado' });
    }

    // Verificar se o email corresponde (se foi convidado por email)
    if (invite.email) {
      const user = await User.findOne({ userId: req.userId });
      
      if (!user || user.email !== invite.email) {
        return res.status(403).json({ message: 'Este convite foi enviado para outro email' });
      }
    }

    // Verificar se o usuário é o dono da wallet
    const wallet = await Wallet.findById(invite.walletId._id);
    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    if (wallet.ownerId === req.userId) {
      return res.status(400).json({ message: 'Você é o dono desta wallet. Não é possível aceitar um convite para sua própria wallet.' });
    }

    // Verificar se já é membro
    const existingMember = await WalletMember.findOne({
      walletId: invite.walletId._id,
      userId: req.userId
    });

    if (existingMember) {
      // Se já é membro, não marcar como aceito (pode ser que o convite já tenha sido aceito antes)
      // Apenas retornar erro informando que já é membro
      return res.status(400).json({ message: 'Você já é membro desta wallet' });
    }

    // Criar membership
    const member = new WalletMember({
      walletId: invite.walletId._id,
      userId: req.userId,
      permission: invite.permission
    });
    await member.save();

    // Atualizar convite
    invite.status = 'accepted';
    invite.acceptedAt = new Date();
    invite.acceptedBy = req.userId;
    await invite.save();

    // Adicionar walletId ao array walletsInvited do usuário
    const user = await User.findOne({ userId: req.userId });
    if (user) {
      if (!user.walletsInvited) {
        user.walletsInvited = [];
      }
      // Verificar se o walletId já não está no array
      const walletIdString = invite.walletId._id.toString();
      if (!user.walletsInvited.some(id => id.toString() === walletIdString)) {
        user.walletsInvited.push(invite.walletId._id);
        await user.save();
      }
    }

    // Recarregar o invite para ter os dados atualizados
    const updatedInvite = await Invite.findOne({ token: req.params.token })
      .populate('walletId');
    
    res.json({ 
      message: 'Convite aceito com sucesso',
      wallet: updatedInvite.walletId ? {
        _id: updatedInvite.walletId._id,
        name: updatedInvite.walletId.name,
        ownerId: updatedInvite.walletId.ownerId
      } : null,
      permission: invite.permission
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// DELETE cancelar convite (apenas dono)
router.delete('/:token', async (req, res) => {
  try {
    const Invite = getInviteModel();
    const Wallet = getWalletModel();

    const invite = await Invite.findOne({ token: req.params.token });
    
    if (!invite) {
      return res.status(404).json({ message: 'Convite não encontrado' });
    }

    // Verificar se o usuário é dono da wallet
    const wallet = await Wallet.findById(invite.walletId);
    if (!wallet || wallet.ownerId !== req.userId) {
      return res.status(403).json({ message: 'Apenas o dono da wallet pode cancelar convites' });
    }

    await Invite.findByIdAndDelete(invite._id);

    res.json({ message: 'Convite cancelado com sucesso' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

module.exports = router;
