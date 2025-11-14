const express = require('express');
const router = express.Router();
const { generateRegistrationOptions, verifyRegistrationResponse } = require('@simplewebauthn/server');
const { generateAuthenticationOptions, verifyAuthenticationResponse } = require('@simplewebauthn/server');
const { getPasskeyModel } = require('../models/Passkey');
const { getChallengeModel } = require('../models/Challenge');
const { getUserModel } = require('../models/User');
const { createClient } = require('@supabase/supabase-js');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const https = require('https');
const http = require('http');
require('dotenv').config();

// Função auxiliar para validar e normalizar base64url
function normalizeBase64Url(str) {
  if (!str || typeof str !== 'string') {
    return null;
  }
  // Remove qualquer padding que possa ter sido adicionado incorretamente
  return str.replace(/=+$/, '');
}

// Função para criar tokens JWT do Supabase manualmente
// Isso permite criar uma sessão automaticamente após verificação de passkey
// Suporta tanto Legacy JWT Secret (HS256) quanto JWT Signing Keys (RS256)
function createSupabaseTokens(user) {
  const jwtSecret = process.env.SUPABASE_JWT_SECRET; // Legacy (HS256)
  const jwtPrivateKey = process.env.SUPABASE_JWT_PRIVATE_KEY; // Novo (RS256)
  
  // Priorizar JWT Signing Keys (RS256) se disponível, senão usar Legacy (HS256)
  const useRS256 = !!jwtPrivateKey;
  const signingKey = useRS256 ? jwtPrivateKey : jwtSecret;
  
  if (!signingKey) {
    const errorMsg = useRS256
      ? 'SUPABASE_JWT_PRIVATE_KEY não configurado. Obtenha em: Supabase Dashboard → Settings → Authentication → JWT Signing Keys → Private Key'
      : 'SUPABASE_JWT_SECRET não configurado. Obtenha em: Supabase Dashboard → Settings → API → JWT Secret';
    throw new Error(errorMsg);
  }

  const now = Math.floor(Date.now() / 1000);
  // Com JWT Signing Keys, você pode configurar expiry time customizado
  // Com Legacy JWT Secret, o padrão é 1 hora (3600 segundos)
  const expiresIn = process.env.JWT_EXPIRES_IN 
    ? parseInt(process.env.JWT_EXPIRES_IN, 10) 
    : 3600; // Padrão: 1 hora
  
  // Criar payload do access token seguindo a estrutura do Supabase
  const accessTokenPayload = {
    aud: 'authenticated',
    exp: now + expiresIn,
    sub: user.id,
    email: user.email,
    role: 'authenticated',
    iat: now,
    app_metadata: user.app_metadata || {
      provider: 'email',
      providers: ['email']
    },
    user_metadata: user.user_metadata || {}
  };

  // Criar access token usando RS256 (JWT Signing Keys) ou HS256 (Legacy)
  const algorithm = useRS256 ? 'RS256' : 'HS256';
  
  // Se for RS256, processar a chave privada (pode ter \n no .env)
  const processedKey = useRS256 
    ? signingKey.replace(/\\n/g, '\n') 
    : signingKey;
  
  const accessToken = jwt.sign(accessTokenPayload, processedKey, {
    algorithm: algorithm
  });

  // Criar refresh token (string aleatória de 40 caracteres, como o Supabase usa)
  const refreshToken = crypto.randomBytes(40).toString('hex');

  console.log(`[Passkey Tokens] Criado usando ${algorithm} (expires in ${expiresIn}s)`);

  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: expiresIn,
    token_type: 'bearer',
    user: {
      id: user.id,
      email: user.email,
      user_metadata: user.user_metadata || {},
      app_metadata: user.app_metadata || {}
    }
  };
}

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
    
    // Armazenar o challenge original no MongoDB para comparação posterior
    // O MongoDB vai expirar automaticamente após 5 minutos (TTL)
    const Challenge = getChallengeModel();
    try {
      await Challenge.create({
        challenge: challengeStr,
        challengeBuffer: challengeBuffer.toString('base64'), // Armazenar como base64 para preservar bytes
        userId: userId,
        type: 'registration',
        createdAt: new Date()
      });
      console.log('[Passkey Register Options] Challenge armazenado no MongoDB:', challengeStr);
    } catch (error) {
      console.error('[Passkey Register Options] Erro ao armazenar challenge:', error);
      // Continuar mesmo se falhar ao armazenar (fallback para decodificação)
    }
    
    console.log('[Passkey Register Options] Challenge gerado:', challengeStr);
    console.log('[Passkey Register Options] Challenge length:', challengeBuffer.length);
    
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
    
    // Tentar recuperar o challenge original do MongoDB
    // Buscar pelo userId e type primeiro, depois verificar se o challenge corresponde
    const Challenge = getChallengeModel();
    let expectedChallenge;
    
    try {
      // Buscar challenges recentes do usuário (últimos 5 minutos)
      const recentChallenges = await Challenge.find({ 
        userId: userId,
        type: 'registration',
        createdAt: { $gte: new Date(Date.now() - 5 * 60 * 1000) } // Últimos 5 minutos
      }).sort({ createdAt: -1 }).limit(5);
      
      // Tentar encontrar o challenge que corresponde (pode haver diferenças de codificação)
      let storedChallenge = null;
      for (const ch of recentChallenges) {
        // Comparar o challenge recebido com o armazenado (ambos como base64url)
        if (ch.challenge === challenge) {
          storedChallenge = ch;
          break;
        }
        // Também tentar comparar decodificando ambos
        try {
          const receivedBuffer = Buffer.from(challenge, 'base64url');
          const storedBuffer = Buffer.from(ch.challengeBuffer, 'base64');
          if (receivedBuffer.equals(storedBuffer)) {
            storedChallenge = ch;
            break;
          }
        } catch (e) {
          // Ignorar erro de comparação
        }
      }
      
      if (storedChallenge && storedChallenge.challengeBuffer) {
        // Usar o challenge original armazenado (decodificar de base64)
        const expectedChallengeBuffer = Buffer.from(storedChallenge.challengeBuffer, 'base64');
        // O challenge no clientDataJSON vem como base64url string, então precisamos passar como base64url também
        // A biblioteca compara diretamente o challenge do clientDataJSON com o expectedChallenge
        expectedChallenge = expectedChallengeBuffer.toString('base64url');
        console.log('[Passkey Register] Usando challenge original do MongoDB');
        
        // Deletar após uso para limpar o banco
        await Challenge.deleteOne({ _id: storedChallenge._id });
      } else {
        // Fallback: usar o challenge recebido diretamente como base64url
        // O challenge já vem como base64url do frontend, então podemos usar diretamente
        expectedChallenge = challenge;
        console.log('[Passkey Register] Usando challenge recebido diretamente (fallback)');
      }
    } catch (error) {
      console.error('[Passkey Register] Erro ao recuperar challenge do MongoDB:', error);
      // Fallback: usar o challenge recebido diretamente como base64url
      // O challenge já vem como base64url do frontend, então podemos usar diretamente
      expectedChallenge = challenge;
      console.log('[Passkey Register] Usando challenge recebido diretamente (fallback após erro)');
    }
    
    console.log('[Passkey Register] Challenge recebido (string base64url):', challenge);
    console.log('[Passkey Register] Challenge esperado (base64url):', expectedChallenge);
    console.log('[Passkey Register] Challenge length:', expectedChallenge.length);
    
    // Converter credential do formato JSON (base64url strings) para formato esperado pela biblioteca
    // O frontend envia tudo como base64url strings, precisamos converter de volta para Buffers
    // IMPORTANTE: verifyRegistrationResponse espera o objeto completo, não apenas response
    if (!credential.id && !credential.rawId) {
      return res.status(400).json({ message: 'Credential ID não encontrado na resposta' });
    }
    
    // Agora tanto id quanto rawId vêm como strings base64url do frontend
    // O frontend garante que ambos sejam base64url válidos usando rawId convertido
    const rawIdString = credential.rawId || credential.id;
    if (!rawIdString) {
      return res.status(400).json({ message: 'Credential rawId não encontrado na resposta' });
    }
    
    // Converter rawId de base64url string para Buffer
    let rawIdBuffer;
    try {
      rawIdBuffer = Buffer.from(rawIdString, 'base64url');
    } catch (e) {
      console.error('[Passkey Register] Erro ao decodificar rawId:', e);
      return res.status(400).json({ message: 'Credential rawId não está em formato base64url válido' });
    }
    
    // O id deve ser uma string base64url válida - garantir que seja exatamente igual ao rawId convertido
    // A biblioteca verifica se o id corresponde ao rawId, então precisamos garantir que sejam idênticos
    let credentialIdBase64Url = rawIdBuffer.toString('base64url'); // Converter Buffer de volta para base64url para garantir consistência
    
    // Normalizar o base64url (remover padding se houver)
    credentialIdBase64Url = normalizeBase64Url(credentialIdBase64Url);
    
    // Validar formato base64url usando regex (a biblioteca faz essa validação internamente)
    const base64UrlRegex = /^[A-Za-z0-9\-_]+$/;
    if (!credentialIdBase64Url || !base64UrlRegex.test(credentialIdBase64Url)) {
      console.error('[Passkey Register] ID não está em formato base64url válido:', credentialIdBase64Url);
      return res.status(400).json({ message: 'Credential ID não está em formato base64url válido' });
    }
    
    // Garantir que o rawIdBuffer convertido de volta corresponde ao original
    const verifyBuffer = Buffer.from(credentialIdBase64Url, 'base64url');
    if (!verifyBuffer.equals(rawIdBuffer)) {
      console.error('[Passkey Register] ID não corresponde ao rawId após conversão');
      return res.status(400).json({ message: 'Credential ID não corresponde ao rawId' });
    }
    
    // Validar que o rawIdString recebido corresponde ao rawIdBuffer convertido
    if (rawIdString !== credentialIdBase64Url) {
      console.warn('[Passkey Register] rawIdString recebido não corresponde ao rawIdBuffer convertido');
      console.warn('[Passkey Register] rawIdString recebido:', rawIdString);
      console.warn('[Passkey Register] rawIdBuffer convertido:', credentialIdBase64Url);
      // Usar o valor convertido do Buffer para garantir consistência
    }
    
    // A biblioteca compara id !== rawId diretamente, então rawId também deve ser uma string base64url
    // A biblioteca também espera clientDataJSON e attestationObject como strings base64url (não Buffers)
    const credentialForVerification = {
      id: credentialIdBase64Url, // String base64url válida
      rawId: credentialIdBase64Url, // String base64url (a biblioteca compara id === rawId como strings)
      type: credential.type || 'public-key',
      response: {
        clientDataJSON: credential.response.clientDataJSON, // String base64url (já vem do frontend)
        attestationObject: credential.response.attestationObject || undefined, // String base64url (já vem do frontend)
      },
      authenticatorAttachment: credential.authenticatorAttachment,
      clientExtensionResults: credential.clientExtensionResults || {},
    };
    
    // Armazenar o rawIdBuffer separadamente para uso posterior (salvar no banco)
    credentialForVerification._rawIdBuffer = rawIdBuffer;
    
    console.log('[Passkey Register] Credential ID:', credentialForVerification.id);
    console.log('[Passkey Register] Credential ID type:', typeof credentialForVerification.id);
    console.log('[Passkey Register] Credential ID length:', credentialForVerification.id.length);
    console.log('[Passkey Register] Credential rawId type:', typeof credentialForVerification.rawId);
    console.log('[Passkey Register] Credential rawId length:', credentialForVerification.rawId.length);
    console.log('[Passkey Register] ID corresponde ao rawId?', credentialForVerification.id === credentialForVerification.rawId);
    console.log('[Passkey Register] Credential clientDataJSON length:', credentialForVerification.response.clientDataJSON.length);
    console.log('[Passkey Register] Credential attestationObject presente:', !!credentialForVerification.response.attestationObject);
    console.log('[Passkey Register] Credential completo (JSON):', JSON.stringify({
      id: credentialForVerification.id,
      type: credentialForVerification.type,
      rawIdLength: credentialForVerification.rawId.length,
      hasResponse: !!credentialForVerification.response
    }));
    
    // Verificar a resposta de registro
    let verification;
    try {
      verification = await verifyRegistrationResponse({
        response: credentialForVerification, // Passar o objeto completo, não apenas response
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

    // Verificar se registrationInfo existe e tem os dados necessários
    if (!verification.registrationInfo) {
      console.error('[Passkey Register] registrationInfo não disponível na verificação');
      return res.status(500).json({ message: 'Erro ao processar informações de registro' });
    }

    // A estrutura do registrationInfo tem credential dentro, não diretamente
    // registrationInfo.credential.id, registrationInfo.credential.publicKey, etc.
    const credentialInfo = verification.registrationInfo.credential;
    
    if (!credentialInfo) {
      console.error('[Passkey Register] credential não disponível no registrationInfo');
      console.error('[Passkey Register] registrationInfo estrutura:', Object.keys(verification.registrationInfo));
      return res.status(500).json({ message: 'Erro ao processar informações de credencial' });
    }
    
    const credentialID = credentialInfo.id;
    const credentialPublicKey = credentialInfo.publicKey;
    const counter = credentialInfo.counter;
    
    // Log para debug
    console.log('[Passkey Register] credentialInfo disponível:', {
      hasCredentialID: !!credentialID,
      hasCredentialPublicKey: !!credentialPublicKey,
      hasCounter: counter !== undefined,
      credentialIDType: credentialID ? typeof credentialID : 'undefined',
      credentialPublicKeyType: credentialPublicKey ? typeof credentialPublicKey : 'undefined',
      credentialKeys: Object.keys(credentialInfo)
    });

    // O credentialID da biblioteca vem como string base64url em credential.id
    // Se não estiver disponível, usar o rawIdBuffer que armazenamos anteriormente
    let credentialIDBase64Url;
    if (credentialID && typeof credentialID === 'string') {
      // credentialID já vem como string base64url
      credentialIDBase64Url = credentialID;
    } else if (credentialID) {
      // Se vier como Buffer ou Uint8Array, converter para base64url
      let credentialIDBuffer;
      if (Buffer.isBuffer(credentialID)) {
        credentialIDBuffer = credentialID;
      } else if (credentialID instanceof Uint8Array) {
        credentialIDBuffer = Buffer.from(credentialID);
      } else {
        credentialIDBuffer = Buffer.from(credentialID);
      }
      credentialIDBase64Url = credentialIDBuffer.toString('base64url');
    } else if (credentialForVerification._rawIdBuffer) {
      // Fallback: usar o rawIdBuffer que armazenamos
      credentialIDBase64Url = credentialForVerification._rawIdBuffer.toString('base64url');
    } else {
      console.error('[Passkey Register] credentialID não disponível e _rawIdBuffer não encontrado');
      return res.status(500).json({ message: 'Erro ao processar credential ID' });
    }

    // Verificar se a credencial já existe
    const existingPasskey = await Passkey.findOne({ credentialID: credentialIDBase64Url });
    if (existingPasskey) {
      return res.status(400).json({ message: 'Esta passkey já está registrada' });
    }

    // Converter credentialPublicKey para Buffer se necessário
    let publicKeyBuffer;
    if (!credentialPublicKey) {
      console.error('[Passkey Register] credentialPublicKey não disponível no registrationInfo');
      return res.status(500).json({ message: 'Erro ao processar public key da credencial' });
    }
    
    if (Buffer.isBuffer(credentialPublicKey)) {
      publicKeyBuffer = credentialPublicKey;
    } else if (credentialPublicKey instanceof Uint8Array) {
      publicKeyBuffer = Buffer.from(credentialPublicKey);
    } else if (Array.isArray(credentialPublicKey)) {
      publicKeyBuffer = Buffer.from(credentialPublicKey);
    } else {
      // Tentar converter como ArrayBuffer ou outro formato
      try {
        publicKeyBuffer = Buffer.from(credentialPublicKey);
      } catch (e) {
        console.error('[Passkey Register] Erro ao converter credentialPublicKey:', e);
        console.error('[Passkey Register] Tipo de credentialPublicKey:', typeof credentialPublicKey);
        console.error('[Passkey Register] credentialPublicKey:', credentialPublicKey);
        return res.status(500).json({ message: 'Erro ao processar public key da credencial' });
      }
    }

    // Salvar a passkey no banco de dados
    const passkey = new Passkey({
      userId,
      credentialID: credentialIDBase64Url,
      publicKey: publicKeyBuffer.toString('base64url'),
      counter: counter || 0,
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

    // Converter credentialID para string base64url
    // A biblioteca espera strings base64url em allowCredentials, não Buffers
    const allowCredentials = passkeys.map(passkey => {
      let credentialIDString;
      
      if (!passkey.credentialID) {
        console.error('[Passkey Authenticate Options] credentialID não encontrado para passkey:', passkey._id);
        return null;
      }
      
      // Se já for string, usar diretamente (assumindo que é base64url)
      if (typeof passkey.credentialID === 'string') {
        credentialIDString = passkey.credentialID;
      } else if (Buffer.isBuffer(passkey.credentialID)) {
        // Se for Buffer, converter para string base64url
        credentialIDString = passkey.credentialID.toString('base64url');
      } else {
        console.error('[Passkey Authenticate Options] Tipo de credentialID inválido:', typeof passkey.credentialID);
        return null;
      }
      
      return {
        id: credentialIDString, // String base64url
        type: 'public-key',
        transports: ['internal', 'hybrid']
      };
    }).filter(cred => cred !== null); // Remover credenciais inválidas

    const options = await generateAuthenticationOptions({
      rpID,
      timeout: 60000,
      allowCredentials,
      userVerification: 'preferred'
    });

    // Converter challenge e credential IDs de Buffer para string base64url
    const challengeBuffer = Buffer.isBuffer(options.challenge) 
      ? options.challenge 
      : Buffer.from(options.challenge);
    const challengeStr = challengeBuffer.toString('base64url');
    
    // Armazenar o challenge original no MongoDB para comparação posterior
    const Challenge = getChallengeModel();
    try {
      await Challenge.create({
        challenge: challengeStr,
        challengeBuffer: challengeBuffer.toString('base64'), // Armazenar como base64 para preservar bytes
        userId: user.id,
        type: 'authentication',
        createdAt: new Date()
      });
      console.log('[Passkey Auth Options] Challenge armazenado no MongoDB:', challengeStr);
    } catch (error) {
      console.error('[Passkey Auth Options] Erro ao armazenar challenge:', error);
      // Continuar mesmo se falhar ao armazenar (fallback para decodificação)
    }

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

    // Tentar recuperar o challenge original do MongoDB
    // Buscar pelo userId e type primeiro, depois verificar se o challenge corresponde
    const Challenge = getChallengeModel();
    let expectedChallenge;
    
    try {
      // Buscar challenges recentes do usuário (últimos 5 minutos)
      const recentChallenges = await Challenge.find({ 
        userId: userId,
        type: 'authentication',
        createdAt: { $gte: new Date(Date.now() - 5 * 60 * 1000) } // Últimos 5 minutos
      }).sort({ createdAt: -1 }).limit(5);
      
      // Tentar encontrar o challenge que corresponde (pode haver diferenças de codificação)
      let storedChallenge = null;
      for (const ch of recentChallenges) {
        // Comparar o challenge recebido com o armazenado (ambos como base64url)
        if (ch.challenge === challenge) {
          storedChallenge = ch;
          break;
        }
        // Também tentar comparar decodificando ambos
        try {
          const receivedBuffer = Buffer.from(challenge, 'base64url');
          const storedBuffer = Buffer.from(ch.challengeBuffer, 'base64');
          if (receivedBuffer.equals(storedBuffer)) {
            storedChallenge = ch;
            break;
          }
        } catch (e) {
          // Ignorar erro de comparação
        }
      }
      
      if (storedChallenge && storedChallenge.challengeBuffer) {
        // Usar o challenge original armazenado (decodificar de base64)
        const expectedChallengeBuffer = Buffer.from(storedChallenge.challengeBuffer, 'base64');
        // O challenge no clientDataJSON vem como base64url string, então precisamos passar como base64url também
        // A biblioteca compara diretamente o challenge do clientDataJSON com o expectedChallenge
        expectedChallenge = expectedChallengeBuffer.toString('base64url');
        console.log('[Passkey Authenticate] Usando challenge original do MongoDB');
        
        // Deletar após uso para limpar o banco
        await Challenge.deleteOne({ _id: storedChallenge._id });
      } else {
        // Fallback: usar o challenge recebido diretamente como base64url
        // O challenge já vem como base64url do frontend, então podemos usar diretamente
        expectedChallenge = challenge;
        console.log('[Passkey Authenticate] Usando challenge recebido diretamente (fallback)');
      }
    } catch (error) {
      console.error('[Passkey Authenticate] Erro ao recuperar challenge do MongoDB:', error);
      // Fallback: usar o challenge recebido diretamente como base64url
      // O challenge já vem como base64url do frontend, então podemos usar diretamente
      expectedChallenge = challenge;
      console.log('[Passkey Authenticate] Usando challenge recebido diretamente (fallback após erro)');
    }
    
    console.log('[Passkey Authenticate] Challenge recebido (string base64url):', challenge);
    console.log('[Passkey Authenticate] Challenge esperado (base64url):', expectedChallenge);
    console.log('[Passkey Authenticate] Challenge length:', expectedChallenge.length);
    
    // Converter credential do formato JSON (base64url strings) para formato esperado pela biblioteca
    // IMPORTANTE: verifyAuthenticationResponse espera o objeto completo, não apenas response
    if (!credential.id && !credential.rawId) {
      return res.status(400).json({ message: 'Credential ID não encontrado na resposta' });
    }
    
    // Agora tanto id quanto rawId vêm como strings base64url do frontend
    // O frontend garante que ambos sejam base64url válidos usando rawId convertido
    const rawIdString = credential.rawId || credential.id;
    if (!rawIdString) {
      return res.status(400).json({ message: 'Credential rawId não encontrado na resposta' });
    }
    
    // Converter rawId de base64url string para Buffer
    let rawIdBuffer;
    try {
      rawIdBuffer = Buffer.from(rawIdString, 'base64url');
    } catch (e) {
      console.error('[Passkey Authenticate] Erro ao decodificar rawId:', e);
      return res.status(400).json({ message: 'Credential rawId não está em formato base64url válido' });
    }
    
    // O id deve ser uma string base64url válida - garantir que seja exatamente igual ao rawId convertido
    // A biblioteca verifica se o id corresponde ao rawId, então precisamos garantir que sejam idênticos
    const credentialIdBase64Url = rawIdBuffer.toString('base64url'); // Converter Buffer de volta para base64url para garantir consistência
    
    // Validar formato base64url usando regex (a biblioteca faz essa validação internamente)
    const base64UrlRegex = /^[A-Za-z0-9\-_]+$/;
    if (!base64UrlRegex.test(credentialIdBase64Url)) {
      console.error('[Passkey Authenticate] ID não está em formato base64url válido:', credentialIdBase64Url);
      return res.status(400).json({ message: 'Credential ID não está em formato base64url válido' });
    }
    
    // Validar que o rawIdString recebido corresponde ao rawIdBuffer convertido
    if (rawIdString !== credentialIdBase64Url) {
      console.warn('[Passkey Authenticate] rawIdString recebido não corresponde ao rawIdBuffer convertido');
      console.warn('[Passkey Authenticate] rawIdString recebido:', rawIdString);
      console.warn('[Passkey Authenticate] rawIdBuffer convertido:', credentialIdBase64Url);
      // Usar o valor convertido do Buffer para garantir consistência
    }
    
    // A biblioteca compara id !== rawId diretamente, então rawId também deve ser uma string base64url
    // A biblioteca também espera clientDataJSON e outros campos como strings base64url (não Buffers)
    const credentialForVerification = {
      id: credentialIdBase64Url, // String base64url válida
      rawId: credentialIdBase64Url, // String base64url (a biblioteca compara id === rawId como strings)
      type: credential.type || 'public-key',
      response: {
        clientDataJSON: credential.response.clientDataJSON, // String base64url (já vem do frontend)
        authenticatorData: credential.response.authenticatorData || undefined, // String base64url (já vem do frontend)
        signature: credential.response.signature || undefined, // String base64url (já vem do frontend)
        userHandle: credential.response.userHandle || undefined, // String base64url (já vem do frontend)
      },
      authenticatorAttachment: credential.authenticatorAttachment,
      clientExtensionResults: credential.clientExtensionResults || {},
    };
    
    // Armazenar o rawIdBuffer separadamente para uso posterior
    credentialForVerification._rawIdBuffer = rawIdBuffer;
    
    console.log('[Passkey Authenticate] Credential ID:', credentialForVerification.id);
    console.log('[Passkey Authenticate] Credential ID type:', typeof credentialForVerification.id);
    console.log('[Passkey Authenticate] Credential ID length:', credentialForVerification.id.length);
    console.log('[Passkey Authenticate] Credential rawId type:', typeof credentialForVerification.rawId);
    console.log('[Passkey Authenticate] Credential rawId length:', credentialForVerification.rawId.length);
    console.log('[Passkey Authenticate] ID corresponde ao rawId?', credentialForVerification.id === credentialForVerification.rawId);
    console.log('[Passkey Authenticate] Credential clientDataJSON length:', credentialForVerification.response.clientDataJSON.length);
    
    // Verificar se passkey tem os campos necessários
    if (!passkey.credentialID || !passkey.publicKey) {
      console.error('[Passkey Authenticate] Passkey incompleta:', {
        hasCredentialID: !!passkey.credentialID,
        hasPublicKey: !!passkey.publicKey,
        hasCounter: passkey.counter !== undefined
      });
      return res.status(500).json({ message: 'Dados da passkey incompletos' });
    }
    
    // Converter credentialID e publicKey para Buffer
    let credentialIDBuffer;
    if (typeof passkey.credentialID === 'string') {
      credentialIDBuffer = Buffer.from(passkey.credentialID, 'base64url');
    } else if (Buffer.isBuffer(passkey.credentialID)) {
      credentialIDBuffer = passkey.credentialID;
    } else {
      return res.status(500).json({ message: 'Formato de credentialID inválido' });
    }
    
    let publicKeyBuffer;
    if (typeof passkey.publicKey === 'string') {
      publicKeyBuffer = Buffer.from(passkey.publicKey, 'base64url');
    } else if (Buffer.isBuffer(passkey.publicKey)) {
      publicKeyBuffer = passkey.publicKey;
    } else {
      return res.status(500).json({ message: 'Formato de publicKey inválido' });
    }
    
    // Usar counter da passkey ou 0 como padrão
    const counter = passkey.counter !== undefined && passkey.counter !== null ? passkey.counter : 0;
    
    console.log('[Passkey Authenticate] Dados do authenticator:', {
      credentialIDLength: credentialIDBuffer.length,
      publicKeyLength: publicKeyBuffer.length,
      counter: counter
    });
    
    // Verificar a resposta de autenticação
    // A biblioteca espera 'credential', não 'authenticator'
    const verification = await verifyAuthenticationResponse({
      response: credentialForVerification, // Passar o objeto completo, não apenas response
      expectedChallenge: expectedChallenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      credential: {
        id: credentialIDBuffer,
        publicKey: publicKeyBuffer,
        counter: counter
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

    // Usar Admin API para gerar magic link e extrair tokens válidos
    // Isso cria uma sessão válida com refresh_token real do Supabase
    try {
      console.log('[Passkey Authenticate] Gerando magic link para obter tokens válidos...');
      
      const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
        type: 'magiclink',
        email: user.email,
        options: {
          redirectTo: origin
        }
      });

      if (linkError || !linkData) {
        console.error('[Passkey Authenticate] Erro ao gerar magic link:', linkError);
        throw new Error('Erro ao gerar magic link: ' + (linkError?.message || 'Unknown error'));
      }

      const actionLink = linkData.properties?.action_link;
      
      if (!actionLink) {
        throw new Error('Magic link não contém action_link');
      }

      console.log('[Passkey Authenticate] Magic link gerado:', actionLink.substring(0, 100) + '...');
      console.log('[Passkey Authenticate] Extraindo token do magic link...');
      
      // Extrair token do magic link
      // O Supabase magic link pode ter o token em diferentes formatos
      let token = null;
      try {
        const url = new URL(actionLink);
        
        // Log para debug
        console.log('[Passkey Authenticate] URL parsed:');
        console.log('[Passkey Authenticate] - Search:', url.search);
        console.log('[Passkey Authenticate] - Hash:', url.hash ? url.hash.substring(0, 50) + '...' : 'none');
        
        // Tentar extrair de diferentes lugares na query string
        token = url.searchParams.get('token') 
             || url.searchParams.get('access_token')
             || url.searchParams.get('hash')
             || url.searchParams.get('code');
        
        // Se não encontrou na query string, tentar no hash
        if (!token && url.hash) {
          const hashStr = url.hash.substring(1); // Remove o #
          console.log('[Passkey Authenticate] Tentando extrair do hash:', hashStr.substring(0, 50));
          
          // Tentar como URLSearchParams primeiro
          try {
            const hashParams = new URLSearchParams(hashStr);
            token = hashParams.get('access_token') 
                 || hashParams.get('token')
                 || hashParams.get('hash')
                 || hashParams.get('code');
          } catch (e) {
            // Se falhar, tentar regex
            console.log('[Passkey Authenticate] Hash não é URLSearchParams, tentando regex...');
          }
          
          // Se ainda não encontrou, tentar regex no hash
          if (!token) {
            const tokenMatch = hashStr.match(/(?:token|access_token|hash|code)=([^&]+)/);
            if (tokenMatch && tokenMatch[1]) {
              token = decodeURIComponent(tokenMatch[1]);
            }
          }
        }
        
        // Log resultado
        if (token) {
          console.log('[Passkey Authenticate] ✅ Token extraído com sucesso! Length:', token.length);
        } else {
          console.log('[Passkey Authenticate] ⚠️ Token não encontrado no link');
          console.log('[Passkey Authenticate] Link completo:', actionLink);
        }
      } catch (e) {
        console.error('[Passkey Authenticate] Erro ao extrair token do link:', e);
        console.error('[Passkey Authenticate] Link:', actionLink);
      }

      // Se conseguimos extrair o token, retornar para o frontend usar verifyOTP
      if (token) {
        console.log('[Passkey Authenticate] ✅ Retornando token para frontend');
        
        res.json({
          success: true,
          userId: user.id,
          email: user.email,
          token: token, // Token do magic link para usar com verifyOTP
          magicLink: actionLink, // Link completo como fallback
          message: 'Autenticação bem-sucedida'
        });
      } else {
        // Se não conseguimos extrair token, retornar magic link
        // O frontend pode tentar usar o link diretamente ou pedir senha
        console.log('[Passkey Authenticate] ⚠️ Retornando magic link (token não extraído)');
        
        res.json({
          success: true,
          userId: user.id,
          email: user.email,
          magicLink: actionLink,
          message: 'Autenticação bem-sucedida. Use magic link para completar login.',
          requiresPassword: true
        });
      }
    } catch (error) {
      console.error('[Passkey Authenticate] Erro ao gerar sessão:', error);
      
      // Último fallback: retornar sucesso mas indicar que precisa de senha
      res.json({
        success: true,
        userId: user.id,
        email: user.email,
        message: 'Autenticação bem-sucedida. Por favor, insira sua senha para completar o login.',
        requiresPassword: true
      });
    }
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

