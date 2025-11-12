const { getWalletModel } = require('../models/Wallet');
const { getWalletMemberModel } = require('../models/WalletMember');

// Middleware para verificar se o usuário tem acesso a uma wallet
const checkWalletAccess = async (req, res, next) => {
  try {
    const walletId = req.params.walletId || req.body.walletId || req.query.walletId;
    
    if (!walletId) {
      return res.status(400).json({ message: 'Wallet ID é obrigatório' });
    }

    const Wallet = getWalletModel();
    const WalletMember = getWalletMemberModel();

    // Verificar se é o dono da wallet
    const wallet = await Wallet.findById(walletId);
    if (!wallet) {
      return res.status(404).json({ message: 'Wallet não encontrada' });
    }

    if (wallet.ownerId === req.userId) {
      req.walletPermission = 'owner';
      req.walletId = walletId;
      return next();
    }

    // Verificar se é membro da wallet
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
    console.error('Erro ao verificar acesso à wallet:', error);
    return res.status(500).json({ message: 'Erro ao verificar acesso à wallet' });
  }
};

// Middleware para verificar se o usuário tem permissão de escrita
const checkWritePermission = async (req, res, next) => {
  try {
    const permission = req.walletPermission;
    
    if (permission !== 'write' && permission !== 'owner') {
      return res.status(403).json({ message: 'Você não tem permissão para modificar esta wallet' });
    }

    next();
  } catch (error) {
    console.error('Erro ao verificar permissão de escrita:', error);
    return res.status(500).json({ message: 'Erro ao verificar permissão' });
  }
};

// Middleware para verificar se o usuário é o dono da wallet
const checkOwnerPermission = async (req, res, next) => {
  try {
    const permission = req.walletPermission;
    
    if (permission !== 'owner') {
      return res.status(403).json({ message: 'Apenas o dono da wallet pode realizar esta ação' });
    }

    next();
  } catch (error) {
    console.error('Erro ao verificar permissão de dono:', error);
    return res.status(500).json({ message: 'Erro ao verificar permissão' });
  }
};

module.exports = { 
  checkWalletAccess, 
  checkWritePermission, 
  checkOwnerPermission 
};

