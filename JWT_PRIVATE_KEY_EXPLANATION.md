# 🔐 Por Que Só Tem Public Key?

## 📋 Situação

O Supabase **por padrão NÃO fornece a Private Key** das JWT Signing Keys por **segurança**. Apenas a **Public Key** está disponível.

**Por quê?**
- A Public Key é usada para **VERIFICAR** tokens (seguro compartilhar)
- A Private Key é usada para **CRIAR** tokens (deve ser secreta)
- O Supabase não quer que ninguém possa criar tokens manualmente sem controle

---

## ✅ Solução Recomendada: Continuar com Legacy JWT Secret

**Use o Legacy JWT Secret (HS256)** - é a solução mais simples e funciona perfeitamente!

### **Vantagens:**
- ✅ **Disponível imediatamente** no Dashboard
- ✅ **Funciona perfeitamente** para nosso caso de uso
- ✅ **Não requer configuração adicional**
- ✅ **1 hora de expiry** é suficiente para passkeys

### **Onde encontrar:**
1. Dashboard → **Settings** → **API**
2. Role até **JWT Settings**
3. Copie o **JWT Secret** (não o Service Role Key!)

---

## 🔄 Alternativa: Importar Private Key Customizada

Se você **realmente** precisar de expiry time > 1 hora, pode importar uma Private Key customizada:

### **Passo 1: Gerar Private Key**

```bash
# Instalar Supabase CLI (se não tiver)
npm install -g supabase

# Gerar chave privada
supabase gen signing-key --algorithm RS256
```

Isso gera uma Private Key que você pode importar.

### **Passo 2: Importar no Supabase**

1. Dashboard → **Settings** → **Authentication** → **JWT Signing Keys**
2. Clique em **Import Key**
3. Cole a Private Key gerada
4. **⚠️ IMPORTANTE:** Guarde a Private Key em local seguro! Ela não pode ser extraída depois.

### **Desvantagens:**
- ⚠️ Mais complexo de configurar
- ⚠️ Você é responsável pela segurança da Private Key
- ⚠️ Se perder a Private Key, não pode recuperar

---

## ❓ Impacto nas API Keys?

**NÃO, isso NÃO implica mudanças nas API Keys!**

As API Keys (`anon` e `service_role`) continuam funcionando normalmente.

**Apenas se você revogar o Legacy JWT Secret** é que precisaria:
- Desabilitar as API Keys `anon` e `service_role` também
- Mas isso não é necessário para nosso caso de uso

---

## 🎯 Recomendação Final

**Use o Legacy JWT Secret (HS256):**

1. ✅ Mais simples
2. ✅ Funciona perfeitamente
3. ✅ 1 hora de expiry é suficiente
4. ✅ Não requer configuração adicional
5. ✅ Disponível imediatamente

**Configure apenas:**
```env
SUPABASE_JWT_SECRET=sua-chave-legacy-aqui
```

**Não precisa configurar:**
- ❌ `SUPABASE_JWT_PRIVATE_KEY` (não disponível por padrão)
- ❌ Importar Private Key customizada (desnecessário)

---

## 📝 Resumo

| Opção | Complexidade | Expiry Time | Recomendado? |
|-------|--------------|-------------|--------------|
| **Legacy JWT Secret** | ⭐ Simples | 1 hora | ✅ **SIM** |
| **JWT Signing Keys (com Private Key customizada)** | ⭐⭐⭐ Complexo | Configurável | ⚠️ Só se precisar > 1 hora |

**Conclusão:** Continue com o Legacy JWT Secret! 🎉

