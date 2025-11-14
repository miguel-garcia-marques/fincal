# ⏰ Entendendo JWT Expiry Time

## ❓ Pergunta Comum

**"O expiry time de 1 hora significa que preciso estar sempre mudando/configurando algo?"**

**Resposta:** **NÃO!** Você configura **UMA VEZ** e funciona automaticamente. 🎉

---

## 🔑 Diferença Importante

### **1. Chave Secreta (SUPABASE_JWT_SECRET)**
- ✅ **Configura UMA VEZ** e nunca muda
- ✅ **Permanente** (a menos que você mude manualmente)
- ✅ Fica no `.env` ou Render e nunca expira

### **2. Token JWT (access_token)**
- ⏰ **Expira após 1 hora** (temporário)
- 🔄 **Renova automaticamente** usando refresh_token
- ✅ Você **não precisa fazer nada** manualmente

---

## 🔄 Como Funciona na Prática

### **Fluxo Automático:**

```
1. Usuário faz login com passkey
   ↓
2. Backend cria access_token (válido por 1 hora)
   ↓
3. Backend cria refresh_token (válido por muito tempo)
   ↓
4. Frontend recebe ambos os tokens
   ↓
5. Frontend cria sessão no Supabase
   ↓
6. Supabase SDK gerencia automaticamente:
   - Quando access_token expira (após 1 hora)
   - Usa refresh_token para obter novo access_token
   - Renovação acontece AUTOMATICAMENTE
   - Usuário não percebe nada
```

---

## 📊 Timeline de um Token

```
Tempo 0:00 → Token criado (válido por 1 hora)
Tempo 0:30 → Token ainda válido ✅
Tempo 0:59 → Token ainda válido ✅
Tempo 1:00 → Token expira ⏰
           → Supabase SDK detecta expiração
           → Usa refresh_token automaticamente
           → Obtém novo access_token
           → Continua funcionando ✅
Tempo 1:30 → Novo token ainda válido ✅
...e assim por diante
```

---

## ✅ O Que Você Precisa Fazer

### **Configuração Inicial (UMA VEZ):**

1. Copiar `SUPABASE_JWT_SECRET` do Dashboard
2. Adicionar no `.env` ou Render
3. **PRONTO!** 🎉

### **Depois Disso:**

- ✅ **Nada!** O sistema funciona automaticamente
- ✅ Tokens são criados automaticamente quando necessário
- ✅ Tokens são renovados automaticamente quando expiram
- ✅ Usuário não precisa fazer nada

---

## 🔍 Detalhes Técnicos

### **Access Token (access_token)**
- **Expiry:** 1 hora (3600 segundos)
- **Uso:** Autenticação em requisições
- **Renovação:** Automática via refresh_token

### **Refresh Token (refresh_token)**
- **Expiry:** Muito longo (dias/semanas)
- **Uso:** Renovar access_token quando expira
- **Renovação:** Automática pelo Supabase SDK

### **Chave Secreta (SUPABASE_JWT_SECRET)**
- **Expiry:** **NUNCA** (permanente)
- **Uso:** Assinar tokens JWT
- **Mudança:** Só se você quiser mudar manualmente

---

## 🎯 Resumo

| Item | Expiry | Você Precisa Fazer Algo? |
|------|--------|--------------------------|
| **SUPABASE_JWT_SECRET** | Nunca expira | Não - configura uma vez |
| **access_token** | 1 hora | Não - renova automaticamente |
| **refresh_token** | Muito longo | Não - renova automaticamente |
| **Sessão do usuário** | Enquanto usar app | Não - gerencia automaticamente |

---

## 💡 Analogia

É como uma **chave de casa**:
- Você tem **UMA chave** (SUPABASE_JWT_SECRET) que nunca muda
- A chave abre a porta (cria tokens)
- Os tokens são como **convites temporários** que expiram
- Mas você pode criar **novos convites** sempre que quiser usando a mesma chave

---

## ✅ Conclusão

**Você configura UMA VEZ e esquece!** 

- ✅ Chave secreta não expira
- ✅ Tokens expiram, mas renovam automaticamente
- ✅ Você não precisa fazer nada manualmente
- ✅ Sistema funciona sozinho

**Configure o `SUPABASE_JWT_SECRET` e está pronto para sempre!** 🎉

