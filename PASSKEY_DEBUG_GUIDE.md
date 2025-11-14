# 🔍 Guia de Debug: Passkey Ainda Pede Senha

## 📋 Checklist de Verificação

### **1. Verificar se SUPABASE_JWT_SECRET está configurado**

**No Backend (Render ou local):**
- Verifique se a variável `SUPABASE_JWT_SECRET` está configurada
- Deve estar em: Render → Environment Variables OU `backend/.env`

**Como verificar:**
- Olhe os logs do backend quando fizer login com passkey
- Procure por: `[Passkey Authenticate] Erro ao criar tokens JWT`
- Se aparecer esse erro, o `SUPABASE_JWT_SECRET` não está configurado

---

### **2. Verificar Logs do Backend**

**O que procurar nos logs:**

✅ **Sucesso:**
```
[Passkey Authenticate] Tokens JWT criados com sucesso para usuário: <user-id>
[Passkey Tokens] Criado usando HS256 (expires in 3600s)
```

❌ **Erro (SUPABASE_JWT_SECRET não configurado):**
```
[Passkey Authenticate] Erro ao criar tokens JWT: SUPABASE_JWT_SECRET não configurado...
```

---

### **3. Verificar Logs do Frontend (Console do Navegador)**

**Abra o Console do Navegador (F12) e procure:**

✅ **Se tokens estão sendo recebidos:**
```
[PasskeyService] Resposta do backend:
[PasskeyService] - success: true
[PasskeyService] - access_token: true
[PasskeyService] - refresh_token: true
```

❌ **Se tokens NÃO estão sendo recebidos:**
```
[PasskeyService] - access_token: false
[PasskeyService] - refresh_token: false
```

**Se isso aparecer, o backend não está retornando tokens!**

---

### **4. Verificar Tentativa de Criar Sessão**

**No Console do Navegador, procure:**

✅ **Sucesso:**
```
[Passkey Login] Tentando criar sessão com tokens JWT...
[AuthService] ✅ Sessão criada com refreshToken
[Passkey Login] ✅ Sessão criada com sucesso!
```

❌ **Erro:**
```
[Passkey Login] ❌ Erro ao criar sessão com tokens JWT: ...
[AuthService] ❌ Erro em setSession: ...
```

---

## 🛠️ Soluções Comuns

### **Problema 1: SUPABASE_JWT_SECRET não configurado**

**Sintomas:**
- Backend retorna `requiresPassword: true`
- Logs mostram erro ao criar tokens JWT

**Solução:**
1. Obter JWT Secret do Supabase Dashboard
2. Adicionar `SUPABASE_JWT_SECRET` no Render ou `.env`
3. Reiniciar o backend

---

### **Problema 2: Backend não retorna tokens**

**Sintomas:**
- `[PasskeyService] - access_token: false`
- `[PasskeyService] - refresh_token: false`

**Solução:**
1. Verificar logs do backend
2. Verificar se `SUPABASE_JWT_SECRET` está correto
3. Verificar se não há erros no backend

---

### **Problema 3: setSession não funciona**

**Sintomas:**
- Tokens são recebidos (`access_token: true`)
- Mas `setSession` falha

**Possíveis causas:**
1. **Refresh Token inválido:** O refresh token gerado manualmente pode não ser aceito pelo Supabase
2. **Access Token inválido:** O token JWT pode não estar no formato correto

**Solução temporária:**
- O código já tem fallback para pedir senha
- Isso funciona, mas não é ideal

**Solução definitiva:**
- Verificar se o token JWT está sendo criado corretamente
- Verificar se o Supabase aceita tokens criados manualmente

---

## 🔍 Debug Passo a Passo

### **Passo 1: Verificar Backend**

1. Faça login com passkey
2. Olhe os logs do backend (Render Dashboard → Logs)
3. Procure por `[Passkey Authenticate]`

**Se aparecer erro:**
- Configure `SUPABASE_JWT_SECRET`
- Reinicie o backend

**Se aparecer sucesso:**
- Continue para Passo 2

---

### **Passo 2: Verificar Frontend**

1. Abra o Console do Navegador (F12)
2. Faça login com passkey
3. Procure por `[PasskeyService]` e `[Passkey Login]`

**Se `access_token: false`:**
- Backend não está retornando tokens
- Verifique Passo 1

**Se `access_token: true` mas `setSession` falha:**
- Problema com criação de sessão
- Verifique Passo 3

---

### **Passo 3: Verificar setSession**

1. No Console, procure por `[AuthService]`
2. Veja qual erro aparece

**Erros comuns:**
- `Invalid refresh token` → Refresh token não é aceito
- `Token expired` → Token expirou muito rápido
- `Invalid token format` → Formato do token está incorreto

---

## 📝 Informações para Reportar

Se ainda não funcionar, me envie:

1. **Logs do Backend:**
   - Procure por `[Passkey Authenticate]`
   - Copie as últimas linhas

2. **Logs do Frontend (Console):**
   - Procure por `[PasskeyService]` e `[Passkey Login]`
   - Copie as mensagens

3. **Configuração:**
   - `SUPABASE_JWT_SECRET` está configurado? (sim/não)
   - Onde está configurado? (Render/.env)

---

## ✅ Checklist Rápido

- [ ] `SUPABASE_JWT_SECRET` configurado no backend?
- [ ] Backend retorna `access_token` e `refresh_token`?
- [ ] Frontend recebe os tokens?
- [ ] `setSession` é chamado?
- [ ] `setSession` cria sessão com sucesso?

Se alguma resposta for "não", siga o guia acima para resolver!

