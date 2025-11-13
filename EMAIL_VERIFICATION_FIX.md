# 🔧 Correção: Email de Verificação Não Está Sendo Enviado

## 🔍 Problema

O email de verificação não está sendo enviado após criar uma conta.

## ✅ Soluções

### **Solução 1: Verificar Configuração do Supabase**

#### 1.1 - Habilitar Confirmação de Email

1. Acesse [Supabase Dashboard](https://app.supabase.com)
2. Vá em **Settings** → **Auth**
3. Na seção **Email Auth**, verifique:
   - ✅ **Enable email confirmations** deve estar **HABILITADO**
   - ✅ **Enable email signup** deve estar **HABILITADO**

#### 1.2 - Configurar SMTP (Importante!)

O Supabase tem limites no SMTP padrão. Para produção, configure SMTP customizado:

1. Em **Settings** → **Auth** → **SMTP Settings**
2. Configure um provedor SMTP:
   - **Gmail** (recomendado para testes)
   - **SendGrid**
   - **Mailgun**
   - **AWS SES**
   - Outro provedor SMTP

**Configuração básica Gmail (para testes):**
```
Host: smtp.gmail.com
Port: 587
Username: seu-email@gmail.com
Password: sua-senha-de-app (não a senha normal!)
```

**⚠️ IMPORTANTE:** Para Gmail, você precisa criar uma "App Password":
1. Acesse https://myaccount.google.com/apppasswords
2. Gere uma senha de app
3. Use essa senha no Supabase (não sua senha normal!)

#### 1.3 - Verificar Rate Limits

O Supabase tem limites no plano gratuito:
- **4 emails por hora** no SMTP padrão
- Se exceder, emails não serão enviados

**Solução:** Configure SMTP customizado (Solução 1.2)

---

### **Solução 2: Verificar Template de Email**

1. Em **Authentication** → **Email Templates**
2. Selecione **Confirm signup**
3. Verifique se o template está configurado corretamente
4. Use o template fornecido em `email_verification_template.html`

---

### **Solução 3: Verificar Logs do Supabase**

1. Em **Logs** → **Auth Logs**
2. Procure por erros relacionados a envio de email
3. Verifique se há mensagens de erro específicas

---

### **Solução 4: Testar em Desenvolvimento**

Para desenvolvimento local, você pode:

1. **Desabilitar confirmação de email temporariamente:**
   - Em **Settings** → **Auth** → **Email Auth**
   - Desmarque **Enable email confirmations**
   - ⚠️ **ATENÇÃO:** Isso permite login sem verificar email (apenas para desenvolvimento!)

2. **Ou usar email de teste:**
   - O Supabase permite emails de teste em desenvolvimento
   - Verifique a aba **Auth** → **Users** para ver emails pendentes

---

### **Solução 5: Verificar Código Flutter**

Verifique se o código está chamando corretamente:

```dart
await _supabase.auth.signUp(
  email: email,
  password: password,
  emailRedirectTo: redirectUrl, // IMPORTANTE: deve estar configurado
);
```

O `emailRedirectTo` deve corresponder a uma URL nas **Redirect URLs** do Supabase.

---

## 🐛 Troubleshooting Passo a Passo

### Passo 1: Verificar se Email Auth está habilitado
- ✅ Settings → Auth → Email Auth → **Enable email signup** = ON
- ✅ Settings → Auth → Email Auth → **Enable email confirmations** = ON

### Passo 2: Verificar SMTP
- ✅ Settings → Auth → SMTP Settings → Configurado?
- ✅ Se não, configure SMTP customizado

### Passo 3: Verificar Rate Limits
- ✅ Verifique se não excedeu 4 emails/hora (plano gratuito)
- ✅ Se sim, aguarde ou configure SMTP customizado

### Passo 4: Verificar Template
- ✅ Authentication → Email Templates → Confirm signup
- ✅ Template está configurado?

### Passo 5: Verificar Logs
- ✅ Logs → Auth Logs → Há erros?

### Passo 6: Testar
- ✅ Criar nova conta de teste
- ✅ Verificar inbox (incluindo spam)
- ✅ Aguardar alguns minutos (pode haver delay)

---

## 📧 Configuração Recomendada para Produção

### **Opção 1: SendGrid (Recomendado)**

1. Crie conta em [SendGrid](https://sendgrid.com)
2. Crie API Key
3. Configure no Supabase:
   ```
   Host: smtp.sendgrid.net
   Port: 587
   Username: apikey
   Password: [sua-api-key-do-sendgrid]
   ```

### **Opção 2: Gmail (Para testes)**

1. Crie App Password no Google Account
2. Configure no Supabase:
   ```
   Host: smtp.gmail.com
   Port: 587
   Username: seu-email@gmail.com
   Password: [app-password-do-google]
   ```

### **Opção 3: Mailgun**

1. Crie conta em [Mailgun](https://www.mailgun.com)
2. Configure SMTP conforme documentação do Mailgun

---

## ✅ Checklist de Verificação

- [ ] Email Auth habilitado no Supabase
- [ ] Email confirmations habilitado
- [ ] SMTP configurado (customizado ou padrão)
- [ ] Template de email configurado
- [ ] Redirect URLs configuradas corretamente
- [ ] Não excedeu rate limits
- [ ] Verificou logs do Supabase
- [ ] Testou criar nova conta
- [ ] Verificou inbox e spam

---

## 🚨 Problemas Comuns

### "Email não chega"
- ✅ Verificar spam/lixo eletrônico
- ✅ Aguardar alguns minutos (pode haver delay)
- ✅ Verificar se não excedeu rate limits
- ✅ Verificar configuração SMTP

### "Erro ao enviar email"
- ✅ Verificar logs do Supabase
- ✅ Verificar credenciais SMTP
- ✅ Verificar se SMTP está configurado corretamente

### "Link de verificação não funciona"
- ✅ Verificar Redirect URLs no Supabase
- ✅ Verificar se URL corresponde à configuração
- ✅ Verificar se link não expirou (24 horas)

---

## 📝 Notas Importantes

1. **SMTP Padrão do Supabase:**
   - Limitado a 4 emails/hora no plano gratuito
   - Pode ter delays
   - Não recomendado para produção

2. **SMTP Customizado:**
   - Recomendado para produção
   - Sem limites (dependendo do provedor)
   - Mais confiável

3. **Desenvolvimento:**
   - Pode desabilitar confirmação temporariamente
   - Ou usar emails de teste
   - Verificar logs para debug

4. **Produção:**
   - SEMPRE configure SMTP customizado
   - Configure template de email profissional
   - Monitore logs regularmente

