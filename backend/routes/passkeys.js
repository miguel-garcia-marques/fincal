const express = require('express');
const router = express.Router();
const { generateRegistrationOptions, verifyRegistrationResponse } = require('@simplewebauthn/server');
const { generateAuthenticationOptions, verifyAuthenticationResponse } = require('@simplewebauthn/server');
const { getPasskeyModel } = require('../models/Passkey');
const { getUserModel } = require('../models/User');
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

// Cliente Admin para operações que precisam de privilégios elevados
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

// Obter o nome do domínio/rpId
function getRPID() {
  if (process.env.RP_ID) {
    return process.env.RP_ID;
  }
  
  // Em desenvolvimento, usar localhost
  if (process.env.NODE_ENV !== 'production') {
    return 'localhost';
  }
  
  // Em produção, tentar extrair do SUPABASE_URL ou usar padrão
  if (process.env.SUPABASE_URL) {
    try {
      const url = new URL(process.env.SUPABASE_URL);
      return url.hostname.replace('.supabase.co', '');
    } catch (e) {
      return 'localhost';
    }
  }
  
  return 'localhost';
}

const rpID = getRPID();
const rpName = 'FinCal';
const origin = process.env.ORIGIN || (process.env.NODE_ENV === 'production' 
  ? `https://${rpID}` 
  : 'http://localhost:8080');

// Helper para verificar autenticação via token Supabase
async function authenticateUser(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Token de autenticação não fornecido' });
    }

    const token = authHeader.substring(7);
    const { data: { user }, error } = await supabase.auth.getUser(token);

    if (error || !user) {
      return res.status(401).json({ message: 'Token inválido ou expirado' });
    }

    req.userId = user.id;
    req.user = user;
    next();
  } catch (error) {
    return res.status(500).json({ message: 'Erro ao verificar autenticação' });
  }
}

// POST /api/passkeys/register/options - Gerar opções de registro
router.post('/register/options', authenticateUser, async (req, res) => {
  try {
    const Passkey = getPasskeyModel();
    const userId = req.userId;
    
    // Buscar passkeys existentes do usuário
    const existingPasskeys = await Passkey.find({ userId });
    // Converter credentialID de base64url string para Buffer
    const excludeCredentials = existingPasskeys.map(passkey => ({
      id: Buffer.from(passkey.credentialID, 'base64url'),
      type: 'public-key',
      transports: ['internal', 'hybrid']
    }));

    // Converter userId (UUID string) para Buffer
    // O userID deve ser um Buffer, não uma string
    const userIDBuffer = Buffer.from(userId, 'utf-8');

    const options = await generateRegistrationOptions({
      rpName,
      rpID,
      userID: userIDBuffer,
      userName: req.user.email || userId,
      userDisplayName: req.user.user_metadata?.display_name || req.user.email || 'Usuário',
      timeout: 60000,
      attestationType: 'none',
      excludeCredentials,
      authenticatorSelection: {
        authenticatorAttachment: 'platform',
        userVerification: 'preferred',
        requireResidentKey: true
      },
      supportedAlgorithmIDs: [-7, -257] // ES256 e RS256
    });

    // Armazenar challenge temporariamente (em produção, usar Redis ou similar)
    // Por simplicidade, vamos armazenar no req.session ou em memória
    // Por enquanto, vamos retornar o challenge e o cliente deve enviá-lo de volta
    // Converter challenge de Buffer para string base64url para envio ao frontend
    // IMPORTANTE: O challenge deve ser preservado exatamente como foi gerado
    const challengeBuffer = Buffer.isBuffer(options.challenge) 
      ? options.challenge 
      : Buffer.from(options.challenge);
    
    // Usar base64url encoding para garantir compatibilidade com WebAuthn
    // O challenge será codificado no clientDataJSON pelo navegador
    const challengeStr = challengeBuffer.toString('base64url');
    
    // Armazenar o challenge original em memória para comparação posterior
    // Em produção, usar Redis ou session storage
    if (!global.passkeyChallenges) {
      global.passkeyChallenges = new Map();
    }
    global.passkeyChallenges.set(challengeStr, challengeBuffer);
    
    console.log('[Passkey Register Options] Challenge gerado:', challengeStr);
    console.log('[Passkey Register Options] Challenge length:', challengeBuffer.length);
    console.log('[Passkey Register Options] Challenge bytes:', Array.from(challengeBuffer));
    
    res.json({
      ...options,
      challenge: challengeStr, // Incluir challenge na resposta como string base64url
      user: {
        ...options.user,
        id: Buffer.isBuffer(options.user.id) 
          ? options.user.id.toString('base64url')
          : options.user.id
      },
      excludeCredentials: options.excludeCredentials?.map(cred => ({
        ...cred,
        id: Buffer.isBuffer(cred.id) ? cred.id.toString('base64url') : cred.id
      }))
    });
  } catch (error) {
    console.error('Erro ao gerar opções de registro:', error);
    res.status(500).json({ message: 'Erro ao gerar opções de registro: ' + error.message });
  }
});

// POST /api/passkeys/register - Registrar nova passkey
router.post('/register', authenticateUser, async (req, res) => {
  try {
    const Passkey = getPasskeyModel();
    const { credential, challenge, deviceType } = req.body;
    
    if (!credential || !challenge) {
      return res.status(400).json({ message: 'Credencial e challenge são obrigatórios' });
    }

    const userId = req.userId;
    
    // Tentar recuperar o challenge original do armazenamento em memória
    // Se não estiver disponível, usar o challenge recebido
    let expectedChallenge;
    if (global.passkeyChallenges && global.passkeyChallenges.has(challenge)) {
      // Usar o challenge original armazenado
      expectedChallenge = global.passkeyChallenges.get(challenge);
      console.log('[Passkey Register] Usando challenge original do armazenamento');
      // Limpar após uso (opcional, mas recomendado para não acumular memória)
      global.passkeyChallenges.delete(challenge);
    } else {
      // Fallback: decodificar o challenge recebido
      if (typeof challenge === 'string') {
        try {
          // Tentar decodificar como base64url
          expectedChallenge = Buffer.from(challenge, 'base64url');
        } catch (e) {
          // Se falhar, tentar como base64 normal
          expectedChallenge = Buffer.from(challenge, 'base64');
        }
      } else if (Buffer.isBuffer(challenge)) {
        expectedChallenge = challenge;
      } else {
        return res.status(400).json({ message: 'Formato de challenge inválido' });
      }
      console.log('[Passkey Register] Usando challenge decodificado (fallback)');
    }
    
    console.log('[Passkey Register] Challenge recebido (string):', challenge);
    console.log('[Passkey Register] Challenge como Buffer (base64url):', expectedChallenge.toString('base64url'));
    console.log('[Passkey Register] Challenge Buffer length:', expectedChallenge.length);
    console.log('[Passkey Register] Challenge Buffer bytes:', Array.from(expectedChallenge));
    
    // Verificar a resposta de registro
    let verification;
    try {
      verification = await verifyRegistrationResponse({
        response: credential,
        expectedChallenge: expectedChallenge,
        expectedOrigin: origin,
        expectedRPID: rpID,
        requireUserVerification: true
      });
    } catch (verifyError) {
      console.error('[Passkey Register] Erro na verificação:', verifyError);
      // Tentar extrair informações do erro
      const errorMessage = verifyError.message || verifyError.toString();
      console.error('[Passkey Register] Mensagem de erro:', errorMessage);
      
      // Se o erro menciona challenge, pode ser problema de codificação
      if (errorMessage.includes('challenge')) {
        return res.status(400).json({ 
          message: `Erro na verificação do challenge: ${errorMessage}. Verifique se o challenge está sendo preservado corretamente.` 
        });
      }
      
      return res.status(400).json({ 
        message: `Erro ao verificar registro: ${errorMessage}` 
      });
    }

    if (!verification.verified || !verification.registrationInfo) {
      console.error('[Passkey Register] Verificação falhou:', {
        verified: verification.verified,
        hasRegistrationInfo: !!verification.registrationInfo
      });
      return res.status(400).json({ message: 'Verificação de registro falhou' });
    }

    const { credentialID, credentialPublicKey, counter } = verification.registrationInfo;

    // Verificar se a credencial já existe
    const existingPasskey = await Passkey.findOne({ credentialID: Buffer.from(credentialID).toString('base64url') });
    if (existingPasskey) {
      return res.status(400).json({ message: 'Esta passkey já está registrada' });
    }

    // Salvar a passkey no banco de dados
    const passkey = new Passkey({
      userId,
      credentialID: Buffer.from(credentialID).toString('base64url'),
      publicKey: Buffer.from(credentialPublicKey).toString('base64url'),
      counter,
      deviceType: deviceType || 'unknown',
      lastUsedAt: new Date()
    });

    await passkey.save();

    res.json({ 
      success: true,
      message: 'Passkey registrada com sucesso',
      credentialID: passkey.credentialID
    });
  } catch (error) {
    console.error('Erro ao registrar passkey:', error);
    res.status(500).json({ message: 'Erro ao registrar passkey: ' + error.message });
  }
});

// POST /api/passkeys/authenticate/options - Gerar opções de autenticação
router.post('/authenticate/options', async (req, res) => {
  try {
    const Passkey = getPasskeyModel();
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({ message: 'Email é obrigatório' });
    }

    // Buscar usuário pelo email no Supabase usando Admin API
    const { data: { users }, error: userError } = await supabaseAdmin.auth.admin.listUsers();
    
    if (userError) {
      console.error('Erro ao buscar usuários:', userError);
      return res.status(500).json({ message: 'Erro ao buscar usuário' });
    }
    
    const user = users?.find(u => u.email === email);
    
    if (!user) {
      // Não revelar que o usuário não existe por segurança
      return res.status(200).json({
        // Retornar opções vazias mas válidas para não revelar que o usuário não existe
        challenge: '',
        allowCredentials: [],
        timeout: 60000,
        rpID
      });
    }

    // Buscar passkeys do usuário
    const passkeys = await Passkey.find({ userId: user.id });
    
    if (passkeys.length === 0) {
      return res.status(404).json({ message: 'Nenhuma passkey encontrada para este usuário' });
    }

    // Converter credentialID de base64url string para Buffer
    const allowCredentials = passkeys.map(passkey => ({
      id: Buffer.from(passkey.credentialID, 'base64url'),
      type: 'public-key',
      transports: ['internal', 'hybrid']
    }));

    const options = await generateAuthenticationOptions({
      rpID,
      timeout: 60000,
      allowCredentials,
      userVerification: 'preferred'
    });

    // Converter challenge e credential IDs de Buffer para string base64url
    const challengeStr = Buffer.isBuffer(options.challenge) 
      ? options.challenge.toString('base64url')
      : options.challenge;

    res.json({
      ...options,
      challenge: challengeStr,
      allowCredentials: options.allowCredentials?.map(cred => ({
        ...cred,
        id: Buffer.isBuffer(cred.id) ? cred.id.toString('base64url') : cred.id
      })),
      userId: user.id // Incluir userId para uso na verificação
    });
  } catch (error) {
    console.error('Erro ao gerar opções de autenticação:', error);
    res.status(500).json({ message: 'Erro ao gerar opções de autenticação: ' + error.message });
  }
});

// POST /api/passkeys/authenticate - Autenticar com passkey
router.post('/authenticate', async (req, res) => {
  try {
    const Passkey = getPasskeyModel();
    const { credential, challenge, userId } = req.body;
    
    if (!credential || !challenge || !userId) {
      return res.status(400).json({ message: 'Credencial, challenge e userId são obrigatórios' });
    }

    // O credential.id vem como string base64url do frontend
    // Precisamos garantir que está no formato correto para busca
    const credentialIdStr = credential.id || credential.rawId;
    
    // Buscar a passkey
    const passkey = await Passkey.findOne({ 
      userId,
      credentialID: credentialIdStr
    });

    if (!passkey) {
      return res.status(404).json({ message: 'Passkey não encontrada' });
    }

    // Converter challenge de string base64url para Buffer se necessário
    const expectedChallenge = typeof challenge === 'string' 
      ? Buffer.from(challenge, 'base64url')
      : challenge;
    
    // Verificar a resposta de autenticação
    const verification = await verifyAuthenticationResponse({
      response: credential,
      expectedChallenge: expectedChallenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: {
        credentialID: Buffer.from(passkey.credentialID, 'base64url'),
        credentialPublicKey: Buffer.from(passkey.publicKey, 'base64url'),
        counter: passkey.counter
      },
      requireUserVerification: true
    });

    if (!verification.verified) {
      return res.status(400).json({ message: 'Verificação de autenticação falhou' });
    }

    // Atualizar contador e última utilização
    passkey.counter = verification.authenticationInfo.newCounter;
    passkey.lastUsedAt = new Date();
    await passkey.save();

    // Buscar usuário no Supabase usando Admin API
    const { data: { user }, error: userError } = await supabaseAdmin.auth.admin.getUserById(userId);
    
    if (userError || !user) {
      return res.status(404).json({ message: 'Usuário não encontrado' });
    }

    // Gerar um link de login mágico temporário usando Admin API
    // Isso permite que o cliente faça login sem senha
    const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
      type: 'magiclink',
      email: user.email,
      options: {
        redirectTo: origin
      }
    });

    if (linkError || !linkData) {
      // Se falhar ao gerar link, retornar informações básicas
      // O cliente precisará fazer login normal uma vez
      return res.json({
        success: true,
        userId: user.id,
        email: user.email,
        requiresPasswordLogin: true,
        message: 'Autenticação bem-sucedida. Por favor, faça login uma vez com senha para ativar sessão.'
      });
    }

    // Extrair token do link gerado
    const magicLink = linkData.properties?.action_link || linkData.properties?.hashed_token;
    
    res.json({
      success: true,
      userId: user.id,
      email: user.email,
      magicLink: magicLink,
      message: 'Autenticação bem-sucedida'
    });
  } catch (error) {
    console.error('Erro ao autenticar com passkey:', error);
    res.status(500).json({ message: 'Erro ao autenticar: ' + error.message });
  }
});

// GET /api/passkeys - Listar passkeys do usuário autenticado
router.get('/', authenticateUser, async (req, res) => {
  try {
    const Passkey = getPasskeyModel();
    const passkeys = await Passkey.find({ userId: req.userId }).select('-publicKey');
    
    res.json(passkeys);
  } catch (error) {
    console.error('Erro ao listar passkeys:', error);
    res.status(500).json({ message: 'Erro ao listar passkeys: ' + error.message });
  }
});

// DELETE /api/passkeys/:id - Deletar passkey
router.delete('/:id', authenticateUser, async (req, res) => {
  try {
    const Passkey = getPasskeyModel();
    const passkey = await Passkey.findOne({ 
      _id: req.params.id,
      userId: req.userId 
    });

    if (!passkey) {
      return res.status(404).json({ message: 'Passkey não encontrada' });
    }

    await Passkey.deleteOne({ _id: req.params.id });
    res.json({ success: true, message: 'Passkey deletada com sucesso' });
  } catch (error) {
    console.error('Erro ao deletar passkey:', error);
    res.status(500).json({ message: 'Erro ao deletar passkey: ' + error.message });
  }
});

module.exports = router;

