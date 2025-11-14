# 🔐 Configuração do SUPABASE_JWT_SECRET

## 📋 O Que É Isso?

O `SUPABASE_JWT_SECRET` (Legacy JWT Secret) é necessário para criar tokens JWT manualmente após a verificação de passkeys, permitindo login automático sem senha.

⚠️ **NOTA:** O Supabase só fornece a **Public Key** das JWT Signing Keys por segurança. Para criar tokens manualmente, use o **Legacy JWT Secret** que está disponível no Dashboard.

---

## 🎯 Passo a Passo

### **1. Obter Legacy JWT Secret do Supabase**

1. Acesse o [Dashboard do Supabase](https://app.supabase.com)
2. Faça login na sua conta
3. Selecione o seu projeto
4. No menu lateral, clique em **Settings** (⚙️)
5. Clique em **API** no submenu
6. Role a página até encontrar a seção **JWT Settings**
7. Você verá o campo **JWT Secret** (é uma string muito longa)
   - ⚠️ **NÃO confunda com "JWT Signing Keys"** (que só tem Public Key)
   - ✅ Procure por **"JWT Secret"** ou **"Legacy JWT Secret"**
8. Clique no ícone de **olho** ou **copiar** ao lado do JWT Secret
9. **Copie o valor completo**

⚠️ **IMPORTANTE:** 
- O **JWT Secret** (Legacy) é diferente da **Service Role Key**
- O JWT Secret é usado para assinar tokens JWT manualmente
- A Service Role Key é usada para Admin API
- O JWT Secret tem expiry time de 1 hora (suficiente para passkeys)

---

### **2. Configurar no Backend (Local)**

**Arquivo:** `backend/.env`

Adicione a linha:

```env
SUPABASE_JWT_SECRET=sua-chave-jwt-secret-aqui
```

**Exemplo:**
```env
SUPABASE_JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long
```

---

### **3. Configurar no Render (Produção)**

1. Acesse [https://dashboard.render.com](https://dashboard.render.com)
2. Faça login e selecione seu serviço (`finance-management-backend`)
3. No menu lateral, clique em **Environment**
4. Clique em **Add Environment Variable**
5. Configure:
   - **Key**: `SUPABASE_JWT_SECRET`
   - **Value**: Cole o JWT Secret que você copiou do Supabase
6. Clique em **Save Changes**
7. O serviço será reiniciado automaticamente

---

## ✅ Verificação

Após configurar, você pode verificar se está funcionando:

1. Faça login com passkey
2. Se funcionar corretamente, você será logado automaticamente **sem precisar de senha**
3. Se não funcionar, verifique os logs do backend para erros relacionados a `SUPABASE_JWT_SECRET`

---

## 🔍 Troubleshooting

### **Erro: "SUPABASE_JWT_SECRET não configurado"**

**Causa:** A variável de ambiente não está configurada.

**Solução:**
1. Verifique se adicionou `SUPABASE_JWT_SECRET` no `.env` (local) ou no Render (produção)
2. Reinicie o servidor backend
3. Verifique se o valor está correto (sem espaços extras, sem quebras de linha)

---

### **Erro: "Token inválido" ou "Sessão não criada"**

**Causa:** O JWT Secret pode estar incorreto ou o token gerado não está no formato correto.

**Solução:**
1. Verifique se copiou o JWT Secret completo (é uma string muito longa)
2. Verifique se não há espaços extras no início ou fim
3. Verifique os logs do backend para mais detalhes

---

### **Fallback Funcionando (pede senha)**

**Causa:** Se o JWT Secret não estiver configurado, o sistema usa um fallback que pede senha.

**Solução:**
1. Configure o `SUPABASE_JWT_SECRET` corretamente
2. Reinicie o backend
3. Tente novamente

---

## 📝 Notas Importantes

1. **Segurança:** 
   - ⚠️ **NUNCA** exponha o JWT Secret no frontend
   - ⚠️ **NUNCA** commite o `.env` com o JWT Secret no Git
   - ⚠️ Mantenha o JWT Secret seguro e privado

2. **Diferença entre JWT Secret e Service Role Key:**
   - **JWT Secret**: Usado para assinar tokens JWT (o que estamos usando)
   - **Service Role Key**: Usado para Admin API (já configurado)

3. **Onde encontrar:**
   - **JWT Secret**: Settings → API → JWT Settings → JWT Secret
   - **Service Role Key**: Settings → API → Project API keys → service_role secret

---

## 🎉 Pronto!

Após configurar o `SUPABASE_JWT_SECRET`, o login com passkey funcionará **automaticamente sem precisar de senha**!

