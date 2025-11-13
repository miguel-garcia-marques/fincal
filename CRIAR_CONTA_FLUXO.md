# 📝 Como Funciona o Processo de Criar Conta

## 🎯 Visão Geral

O processo de criação de conta no FinCal é dividido em **2 cenários principais**, dependendo se o Supabase cria uma sessão imediatamente ou não.

---

## 📋 Fluxo Completo

### **Cenário 1: Com Sessão Imediata** (Mais comum)

Quando o Supabase cria uma sessão automaticamente após o signup:

```
1. Usuário preenche formulário
   ↓
2. Criar conta no Supabase
   ↓
3. Supabase retorna usuário + sessão
   ↓
4. Atualizar nome no Supabase
   ↓
5. Criar usuário no MongoDB
   ↓
6. Verificar sincronização (nome em ambos)
   ↓
7. Navegar para seleção de foto de perfil
   ↓
8. Usuário escolhe foto (ou pula)
   ↓
9. Upload da foto (se escolhida)
   ↓
10. Criar wallet pessoal (se necessário)
    ↓
11. Redirecionar para home ou aceitar convite
```

### **Cenário 2: Sem Sessão Imediata** (Requer verificação de email)

Quando o Supabase não cria sessão (requer verificação de email primeiro):

```
1. Usuário preenche formulário
   ↓
2. Criar conta no Supabase
   ↓
3. Supabase retorna usuário SEM sessão
   ↓
4. Guardar nome e email em SharedPreferences
   ↓
5. Navegar para tela de verificação de email
   ↓
6. Usuário verifica email no inbox
   ↓
7. Clica no link de verificação
   ↓
8. Volta para o app (agora com sessão)
   ↓
9. Criar usuário no MongoDB (com nome guardado)
   ↓
10. Navegar para seleção de foto de perfil
    ↓
11. Resto do fluxo igual ao Cenário 1
```

---

## 🔍 Detalhamento Passo a Passo

### **PASSO 1: Preenchimento do Formulário**

**Arquivo:** `lib/screens/login_screen.dart`

O usuário preenche:
- ✅ **Nome** (obrigatório, mínimo 2 caracteres)
- ✅ **Email** (obrigatório, deve conter @)
- ✅ **Senha** (obrigatória, mínimo 6 caracteres)

**Validação:**
```dart
- Nome: não vazio, mínimo 2 caracteres
- Email: não vazio, deve conter @
- Senha: não vazio, mínimo 6 caracteres (apenas no signup)
```

---

### **PASSO 2: Criar Conta no Supabase**

**Arquivo:** `lib/services/auth_service.dart` → `signUpWithEmail()`

```dart
await _supabase.auth.signUp(
  email: email,
  password: password,
  data: {'display_name': displayName},
  emailRedirectTo: redirectUrl, // URL para redirecionar após verificação
);
```

**O que acontece:**
1. Supabase cria o usuário
2. Envia email de verificação (se configurado)
3. Retorna `AuthResponse` com:
   - `user`: dados do usuário criado
   - `session`: sessão ativa (se email já confirmado ou se não requer verificação)

---

### **PASSO 3: Decisão - Com ou Sem Sessão?**

**Arquivo:** `lib/screens/login_screen.dart` → linha 510

```dart
if (session != null) {
  // CENÁRIO 1: Com sessão - continuar imediatamente
} else {
  // CENÁRIO 2: Sem sessão - ir para verificação de email
}
```

---

### **PASSO 4A: Com Sessão - Criar no MongoDB**

**Arquivo:** `lib/screens/login_screen.dart` → linhas 514-562

**4.1 - Atualizar nome no Supabase:**
```dart
await _authService.updateDisplayName(userName);
```
- Atualiza o campo `display_name` no Supabase Auth

**4.2 - Criar usuário no MongoDB:**
```dart
await _userService.createOrUpdateUser(userName);
```
- Cria registro na collection `users` do MongoDB
- Vincula ao `userId` do Supabase
- Cria wallet pessoal automaticamente

**4.3 - Verificar sincronização:**
```dart
final createdUser = await _userService.getCurrentUser(forceRefresh: true);
if (createdUser.name != userName) {
  // Tentar corrigir sincronização
}
```
- Garante que o nome está igual em Supabase e MongoDB

**4.4 - Navegar para seleção de foto:**
```dart
Navigator.pushReplacement(
  ProfilePictureSelectionScreen(
    email: email,
    inviteToken: inviteToken,
  ),
);
```

---

### **PASSO 4B: Sem Sessão - Guardar Dados Temporários**

**Arquivo:** `lib/screens/login_screen.dart` → linhas 605-620

**Guardar em SharedPreferences:**
```dart
await prefs.setString('pending_user_name', userName);
await prefs.setString('pending_user_email', email);
```

**Navegar para verificação:**
```dart
Navigator.pushReplacement(
  EmailVerificationScreen(
    email: email,
    inviteToken: inviteToken,
  ),
);
```

---

### **PASSO 5: Seleção de Foto de Perfil**

**Arquivo:** `lib/screens/profile_picture_selection_screen.dart`

**Opções do usuário:**
1. ✅ **Escolher foto** (galeria ou câmera)
2. ⏭️ **Pular** (sem foto)

**Se escolher foto:**
```dart
1. Selecionar imagem
2. Converter para bytes
3. Upload para Supabase Storage
4. Obter URL da foto
5. Atualizar perfil do usuário com URL
```

**Se pular:**
- Continua sem foto de perfil (pode adicionar depois)

**Após foto (ou pular):**
- Navega para `AuthWrapper`
- `AuthWrapper` redireciona para:
  - **Home** (se já tem wallet)
  - **Wallet Selection** (se tem múltiplas wallets)
  - **Aceitar Convite** (se há `inviteToken`)

---

### **PASSO 6: Verificação de Email** (apenas se sem sessão)

**Arquivo:** `lib/screens/email_verification_screen.dart`

**O que acontece:**
1. Usuário recebe email do Supabase
2. Clica no link de verificação
3. Supabase redireciona de volta para o app
4. App detecta que email foi verificado
5. Cria sessão automaticamente
6. Recupera dados guardados (`pending_user_name`, `pending_user_email`)
7. Cria usuário no MongoDB com nome guardado
8. Navega para seleção de foto (PASSO 5)

---

## 🔄 Tratamento de Erros

### **Erro no Supabase:**
- Faz logout
- Mostra mensagem: "Erro ao criar conta no Supabase"
- Usuário pode tentar novamente

### **Erro no MongoDB:**
- Faz logout
- Mostra mensagem: "Erro ao criar conta no servidor (MongoDB)"
- Usuário pode tentar novamente

### **Falha de Sincronização:**
- Tenta corrigir automaticamente (retry)
- Se falhar após retry, mostra erro
- Faz logout para estado limpo

---

## 📦 Dados Criados

### **No Supabase:**
- ✅ Usuário autenticado
- ✅ `display_name` (nome do usuário)
- ✅ Email verificado (após verificação)
- ✅ Foto de perfil (se escolhida) → URL no Storage

### **No MongoDB:**
- ✅ Registro na collection `users`:
  - `userId`: ID do Supabase
  - `email`: email do usuário
  - `name`: nome do usuário
  - `profilePictureUrl`: URL da foto (se houver)
  - `personalWalletId`: ID da wallet pessoal
  - `walletsInvited`: array de wallets convidadas

### **Wallet Pessoal:**
- ✅ Criada automaticamente
- ✅ Nome: "Minha Carteira Calendário"
- ✅ `ownerId`: userId do usuário
- ✅ Membership criada com permissão `owner`

---

## 🎯 Fluxo com Convite

Se o usuário tem um `inviteToken` (foi convidado para uma wallet):

1. Todo o fluxo acima acontece normalmente
2. Após criar conta e selecionar foto
3. Se houver `inviteToken`, tenta aceitar automaticamente:
   ```dart
   await walletService.acceptInvite(inviteToken);
   ```
4. Se aceitar com sucesso:
   - Mostra mensagem: "Convite aceito com sucesso!"
   - Navega para home (com acesso à wallet)
5. Se falhar:
   - Navega para `InviteAcceptScreen` para tentar novamente

---

## 🔐 Segurança

### **Validações:**
- ✅ Email único (Supabase valida)
- ✅ Senha mínima de 6 caracteres
- ✅ Nome mínimo de 2 caracteres
- ✅ Email deve conter @

### **Proteções:**
- ✅ Senha nunca é armazenada em texto plano
- ✅ Tokens de autenticação gerenciados pelo Supabase
- ✅ Verificação de email obrigatória (configurável no Supabase)
- ✅ Rate limiting no backend

---

## 📱 Experiência do Usuário

### **Tempo estimado:**
- **Com sessão imediata:** ~30 segundos
- **Com verificação de email:** ~2-5 minutos (depende do email)

### **Telas que o usuário vê:**
1. **Login Screen** (formulário de criação)
2. **Profile Picture Selection** (escolher foto)
3. **Home** ou **Wallet Selection** (tela principal)

### **Se precisar verificar email:**
1. **Login Screen** (formulário)
2. **Email Verification Screen** (aguardar verificação)
3. **Profile Picture Selection** (após verificar)
4. **Home** ou **Wallet Selection**

---

## 🐛 Troubleshooting

### **"Erro ao criar conta no Supabase"**
- Verificar conexão com internet
- Verificar se email já existe
- Verificar configuração do Supabase

### **"Erro ao criar conta no servidor (MongoDB)"**
- Verificar se backend está rodando
- Verificar conexão MongoDB
- Verificar logs do backend

### **"Email não verificado"**
- Verificar inbox (incluindo spam)
- Clicar no link de verificação
- Aguardar alguns segundos após clicar

### **Foto não aparece após upload**
- Verificar permissões do Supabase Storage
- Verificar se URL foi salva corretamente
- Tentar fazer refresh da tela

---

## 📝 Resumo Visual

```
┌─────────────────────────────────────┐
│  1. Preencher Formulário            │
│     (Nome, Email, Senha)            │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  2. Criar no Supabase               │
│     (signUp)                         │
└──────────────┬──────────────────────┘
               │
        ┌──────┴──────┐
        │             │
        ▼             ▼
   Com Sessão    Sem Sessão
        │             │
        │             ▼
        │      ┌──────────────────┐
        │      │ Guardar dados    │
        │      │ temporários      │
        │      └────────┬─────────┘
        │               │
        │               ▼
        │      ┌──────────────────┐
        │      │ Verificar Email  │
        │      └────────┬─────────┘
        │               │
        │               ▼
        │      ┌──────────────────┐
        │      │ Criar MongoDB    │
        │      └────────┬─────────┘
        │               │
        └───────┬───────┘
                │
                ▼
┌─────────────────────────────────────┐
│  3. Selecionar Foto                 │
│     (ou pular)                      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  4. Criar Wallet Pessoal            │
│     (automático)                     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  5. Redirecionar                    │
│     (Home / Wallet Selection)       │
└─────────────────────────────────────┘
```

---

## ✅ Checklist de Criação de Conta

- [ ] Formulário preenchido corretamente
- [ ] Conta criada no Supabase
- [ ] Nome atualizado no Supabase
- [ ] Usuário criado no MongoDB
- [ ] Wallet pessoal criada
- [ ] Foto de perfil selecionada (opcional)
- [ ] Email verificado (se necessário)
- [ ] Redirecionado para tela principal

