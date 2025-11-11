const express = require('express');
const router = express.Router();
const { getUserModel } = require('../models/User');
const { authenticateUser } = require('../middleware/auth');
const { validateUser } = require('../middleware/validation');

// Aplicar middleware de autenticação em todas as rotas
router.use(authenticateUser);

// GET obter dados do usuário atual
router.get('/me', async (req, res) => {
  try {
    const User = getUserModel();
    const user = await User.findOne({ userId: req.userId });
    
    if (!user) {
      return res.status(404).json({ message: 'Usuário não encontrado' });
    }
    
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

// POST criar ou atualizar usuário
router.post('/', validateUser, async (req, res) => {
  try {
    const User = getUserModel();
    const { name } = req.body;
    
    if (!name || name.trim().length === 0) {
      return res.status(400).json({ message: 'Nome é obrigatório' });
    }
    
    // Buscar usuário existente
    let user = await User.findOne({ userId: req.userId });
    
    if (user) {
      // Atualizar usuário existente
      user.name = name.trim();
      user.email = req.user.email || user.email;
      user.updatedAt = new Date();
      await user.save();
    } else {
      // Criar novo usuário
      user = new User({
        userId: req.userId,
        email: req.user.email,
        name: name.trim(),
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

