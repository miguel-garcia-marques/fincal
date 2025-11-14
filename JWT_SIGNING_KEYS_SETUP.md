# 🔐 JWT Signing Keys vs Legacy JWT Secret

## 📊 Diferenças

| Aspecto | Legacy JWT Secret | JWT Signing Keys |
|---------|-------------------|------------------|
| **Algoritmo** | HS256 (simétrico) | RS256 (assimétrico) |
| **Expiry Time** | 1 hora (fixo) | Configurável |
| **Segurança** | Menor (chave compartilhada) | Maior (chave privada/pública) |
| **Status** | Deprecated | Recomendado |
| **Uso** | Simples | Mais complexo |

---

## 🎯 Qual Usar?

### **Legacy JWT Secret (HS256)** - Atual
- ✅ **Mais simples** de implementar
- ✅ **Funciona imediatamente** (já implementado)
- ⚠️ **Limitação:** Expiry time fixo de 1 hora
- ⚠️ **Status:** Deprecated pelo Supabase

### **JWT Signing Keys (RS256)** - Recomendado
- ✅ **Mais seguro** (chaves assimétricas)
- ✅ **Expiry time configurável**
- ✅ **Recomendado pelo Supabase**
- ⚠️ **Mais complexo** de implementar

---

## 🚀 Como Usar JWT Signing Keys

### **Passo 1: Obter Chave Privada do Supabase**

1. Acesse o [Dashboard do Supabase](https://app.supabase.com)
2. Vá em **Settings** → **Authentication** → **JWT Signing Keys**
3. Se você ainda não migrou:
   - Clique em **Migrate JWT Secret** (isso importa o Legacy JWT Secret)
   - Clique em **Rotate Keys** para criar novas chaves
4. Você verá:
   - **Public Key** (para verificar tokens)
   - **Private Key** (para assinar tokens) ⚠️ **COPIE ESTA**
5. Copie a **Private Key** completa (é uma chave PEM)

### **Passo 2: Instalar Dependência**

O `jsonwebtoken` já suporta RS256, mas precisamos garantir que está instalado:

```bash
cd backend
npm install jsonwebtoken
```

### **Passo 3: Configurar Variável de Ambiente**

**Arquivo:** `backend/.env`

```env
# Remover ou comentar o Legacy JWT Secret
# SUPABASE_JWT_SECRET=...

# Adicionar Private Key do JWT Signing Keys
SUPABASE_JWT_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...\n-----END PRIVATE KEY-----
```

⚠️ **IMPORTANTE:** 
- A chave privada tem múltiplas linhas
- No `.env`, use `\n` para quebras de linha
- Ou use aspas triplas se seu sistema suportar

**No Render:**
- Adicione `SUPABASE_JWT_PRIVATE_KEY` como variável de ambiente
- Cole a chave privada completa (com quebras de linha)

### **Passo 4: Atualizar Código do Backend**

O código será atualizado para usar RS256 ao invés de HS256.

---

## 📝 Notas Importantes

1. **Expiry Time Configurável:**
   - Com JWT Signing Keys, você pode configurar o expiry time no payload
   - Exemplo: `expiresIn: 7200` para 2 horas

2. **Migração:**
   - Você pode migrar gradualmente
   - Tokens antigos (HS256) continuarão funcionando até expirarem
   - Novos tokens usarão RS256

3. **Segurança:**
   - A chave privada deve ser mantida **SECRETA**
   - Nunca exponha no frontend
   - Nunca commite no Git

---

## 🔄 Migração Gradual

Se quiser migrar gradualmente:

1. Implementar suporte para ambos (HS256 e RS256)
2. Tentar RS256 primeiro, fallback para HS256
3. Depois de testar, remover suporte para HS256

---

## ❓ Qual Escolher?

**Recomendação:**
- **Se precisa de expiry time > 1 hora:** Use JWT Signing Keys (RS256)
- **Se 1 hora é suficiente:** Continue com Legacy JWT Secret (HS256) por enquanto

**Nota:** O Supabase está deprecando o Legacy JWT Secret, então eventualmente você precisará migrar para JWT Signing Keys.

