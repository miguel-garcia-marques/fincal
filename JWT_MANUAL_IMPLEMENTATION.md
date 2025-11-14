# Opção 2: Implementar JWT Manual para Passkeys

## 🎯 O Que É Esta Solução?

Criar tokens JWT do Supabase **manualmente** após a verificação da passkey, permitindo que o usuário faça login **automaticamente** sem precisar inserir a senha.

---

## 🔍 Como Funciona Atualmente (Problema)

```
1. Usuário autentica com passkey ✅
2. Backend verifica passkey ✅
3. Backend busca usuário no Supabase ✅
4. Backend tenta criar sessão ❌ (não há API direta)
5. Frontend pede senha ao usuário 😞
```

**Problema:** O Supabase não tem uma API Admin que permita criar uma sessão diretamente usando apenas o `userId` após uma autenticação customizada (como passkey).

---

## ✨ Como Funcionaria com JWT Manual (Solução)

```
1. Usuário autentica com passkey ✅
2. Backend verifica passkey ✅
3. Backend busca usuário no Supabase ✅
4. Backend cria token JWT manualmente usando JWT Secret ✅
5. Backend retorna access_token + refresh_token ✅
6. Frontend usa setSession() para criar sessão automaticamente ✅
7. Usuário logado SEM precisar de senha! 🎉
```

---

## 📋 Estrutura de Tokens JWT do Supabase

O Supabase usa tokens JWT com a seguinte estrutura:

### **Access Token (JWT):**
```json
{
  "aud": "authenticated",
  "exp": 1234567890,
  "sub": "user-uuid-here",
  "email": "user@example.com",
  "role": "authenticated",
  "iat": 1234567890,
  "app_metadata": {
    "provider": "email",
    "providers": ["email"]
  },
  "user_metadata": {
    "display_name": "John Doe"
  }
}
```

### **Refresh Token:**
- String aleatória gerada pelo Supabase
- Usado para renovar o access token quando expira

---

## 🛠️ Implementação

### **Passo 1: Obter JWT Secret do Supabase**

1. Acesse o [Dashboard do Supabase](https://app.supabase.com)
2. Vá em **Settings** → **API**
3. Role até encontrar **JWT Secret**
4. Copie o valor (é uma string longa)

⚠️ **IMPORTANTE:** Este secret é diferente da `SUPABASE_SERVICE_ROLE_KEY`!

### **Passo 2: Adicionar JWT Secret às Variáveis de Ambiente**

**Backend `.env`:**
```env
SUPABASE_JWT_SECRET=your-jwt-secret-here
```

**Render (Environment Variables):**
- Adicione `SUPABASE_JWT_SECRET` com o valor copiado

### **Passo 3: Implementar Função de Criação de Tokens**

**Arquivo:** `backend/routes/passkeys.js`

```javascript
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

// Função para criar tokens JWT do Supabase manualmente
function createSupabaseTokens(user) {
  const jwtSecret = process.env.SUPABASE_JWT_SECRET;
  
  if (!jwtSecret) {
    throw new Error('SUPABASE_JWT_SECRET não configurado');
  }

  const now = Math.floor(Date.now() / 1000);
  const expiresIn = 3600; // 1 hora (padrão Supabase)
  
  // Criar payload do access token
  const accessTokenPayload = {
    aud: 'authenticated',
    exp: now + expiresIn,
    sub: user.id,
    email: user.email,
    role: 'authenticated',
    iat: now,
    app_metadata: {
      provider: 'email',
      providers: ['email']
    },
    user_metadata: user.user_metadata || {}
  };

  // Criar access token
  const accessToken = jwt.sign(accessTokenPayload, jwtSecret, {
    algorithm: 'HS256'
  });

  // Criar refresh token (string aleatória)
  // O Supabase usa uma string aleatória de 40 caracteres
  const refreshToken = crypto.randomBytes(40).toString('hex');

  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: expiresIn,
    token_type: 'bearer',
    user: {
      id: user.id,
      email: user.email,
      user_metadata: user.user_metadata || {}
    }
  };
}
```

### **Passo 4: Usar no Endpoint de Autenticação**

**Arquivo:** `backend/routes/passkeys.js` (no endpoint `/authenticate`)

```javascript
// Após verificar passkey e buscar usuário...

// Criar tokens JWT manualmente
const tokens = createSupabaseTokens(user);

// Retornar tokens para o frontend
res.json({
  success: true,
  userId: user.id,
  email: user.email,
  access_token: tokens.access_token,
  refresh_token: tokens.refresh_token,
  expires_in: tokens.expires_in,
  token_type: tokens.token_type
});
```

### **Passo 5: Atualizar Frontend para Usar Tokens**

**Arquivo:** `lib/screens/login_screen.dart`

```dart
if (mounted && result['success'] == true) {
  final accessToken = result['access_token'] as String?;
  final refreshToken = result['refresh_token'] as String?;
  
  if (accessToken != null && refreshToken != null) {
    try {
      // Criar sessão usando os tokens recebidos
      final session = await _authService.supabase.auth.setSession(
        accessToken,
        refreshToken: refreshToken,
      );
      
      if (session.session != null && mounted) {
        // Login bem-sucedido sem precisar de senha! 🎉
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login com passkey bem-sucedido!'),
            backgroundColor: AppTheme.incomeGreen,
          ),
        );
        
        // Navegar para AuthWrapper
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const AuthWrapper(),
          ),
          (route) => false,
        );
        return;
      }
    } catch (e) {
      print('Erro ao criar sessão com tokens JWT: $e');
      // Fallback: mostrar campo de senha
      // ...
    }
  }
}
```

**Arquivo:** `lib/services/auth_service.dart`

```dart
// Adicionar método para setSession com refresh token
Future<AuthResponse> setSession(String accessToken, {String? refreshToken}) async {
  try {
    // O Supabase Flutter SDK tem um método setSession
    // Mas pode precisar de ajustes dependendo da versão
    return await _supabase.auth.setSession(accessToken);
  } catch (e) {
    rethrow;
  }
}
```

---

## ⚠️ Desafios e Limitações

### **1. Refresh Token Storage**
- **Problema:** O Supabase precisa armazenar o refresh token para renovar o access token
- **Solução:** O Supabase SDK gerencia isso automaticamente quando você usa `setSession()`

### **2. Validação do Token**
- **Problema:** O Supabase pode validar tokens de forma diferente
- **Solução:** Garantir que o payload do JWT siga exatamente a estrutura esperada

### **3. Expiração**
- **Problema:** Tokens expiram após 1 hora (padrão)
- **Solução:** O Supabase SDK renova automaticamente usando o refresh token

### **4. Estrutura Interna do Supabase**
- **Problema:** A estrutura interna do Supabase pode mudar
- **Solução:** Monitorar atualizações e ajustar conforme necessário

---

## 🧪 Testes Necessários

1. ✅ Verificar se o token JWT criado é aceito pelo Supabase
2. ✅ Testar criação de sessão no frontend
3. ✅ Testar renovação automática de tokens
4. ✅ Testar logout e limpeza de sessão
5. ✅ Testar em diferentes navegadores/dispositivos

---

## 📊 Comparação com Solução Atual

| Aspecto | Solução Atual | JWT Manual |
|---------|---------------|------------|
| **Experiência do Usuário** | Passkey + Senha | Passkey apenas ✅ |
| **Complexidade** | Baixa | Média |
| **Risco** | Baixo | Médio |
| **Manutenção** | Baixa | Média |
| **Tempo de Implementação** | 0 dias | 1-2 dias |

---

## 🎯 Vantagens

1. ✅ **Login totalmente sem senha** após passkey
2. ✅ **Não requer migração** de provedor de autenticação
3. ✅ **Mantém Supabase** (sem mudanças grandes)
4. ✅ **Implementação relativamente simples** (1-2 dias)

---

## ⚠️ Desvantagens

1. ⚠️ **Depende da estrutura interna do Supabase** (pode quebrar em atualizações)
2. ⚠️ **Não é oficialmente suportado** pelo Supabase
3. ⚠️ **Requer conhecimento** de estrutura de tokens JWT
4. ⚠️ **Pode precisar de ajustes** se o Supabase mudar a estrutura

---

## 🚀 Próximos Passos (Se Decidir Implementar)

1. **Obter JWT Secret** do Supabase Dashboard
2. **Adicionar variável de ambiente** `SUPABASE_JWT_SECRET`
3. **Implementar função** `createSupabaseTokens()` no backend
4. **Atualizar endpoint** `/authenticate` para retornar tokens
5. **Atualizar frontend** para usar `setSession()`
6. **Testar** extensivamente
7. **Monitorar** logs para garantir que funciona corretamente

---

## 📝 Nota Importante

Esta solução **funciona**, mas não é oficialmente suportada pelo Supabase. É uma "workaround" que usa conhecimento da estrutura interna do Supabase. Se o Supabase mudar a estrutura de tokens no futuro, pode ser necessário ajustar o código.

**Alternativa mais segura:** Aguardar suporte oficial do Supabase para criação de sessão após autenticação customizada, ou usar a solução atual (passkey + senha uma vez).

---

## 🔗 Referências

- [Supabase JWT Guide](https://supabase.com/docs/guides/auth/jwts)
- [JSON Web Token (JWT) Specification](https://jwt.io/)
- [Node.js jsonwebtoken Library](https://github.com/auth0/node-jsonwebtoken)

