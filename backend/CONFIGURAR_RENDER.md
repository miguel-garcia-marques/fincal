# Configurar Variáveis de Ambiente no Render

## 🔧 Passo a Passo

### 1. Acessar o Painel do Render

1. Acesse [https://dashboard.render.com](https://dashboard.render.com)
2. Faça login na sua conta
3. Clique no seu serviço (finance-management-backend)

### 2. Configurar Variáveis de Ambiente

1. No menu lateral, clique em **Environment**
2. Clique em **Add Environment Variable** para cada variável abaixo

### 3. Variáveis Necessárias

Adicione as seguintes variáveis:

#### MONGODB_URI (OBRIGATÓRIA)

**Como obter a connection string do MongoDB Atlas:**

1. Acesse [MongoDB Atlas](https://www.mongodb.com/cloud/atlas)
2. Vá em **Database** → **Connect**
3. Escolha **Connect your application**
4. Copie a connection string (algo como):
   ```
   mongodb+srv://username:password@cluster.mongodb.net/
   ```
5. **IMPORTANTE**: Substitua `<password>` pela senha do seu usuário do banco
6. Adicione o nome do banco no final:
   ```
   mongodb+srv://username:password@cluster.mongodb.net/fincal
   ```

**No Render:**
- **Key**: `MONGODB_URI`
- **Value**: A connection string completa (ex: `mongodb+srv://user:pass@cluster.mongodb.net/fincal`)

#### SUPABASE_URL

- **Key**: `SUPABASE_URL`
- **Value**: `https://fjuedycchyiynyqivkch.supabase.co`

#### SUPABASE_ANON_KEY

- **Key**: `SUPABASE_ANON_KEY`
- **Value**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZqdWVkeWNjaHlpeW55cWl2a2NoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI2MTgwOTIsImV4cCI6MjA3ODE5NDA5Mn0.vIeykvK-puQx8q52AARQY8fLl_7EvzL8Vz7VFANKBNo`

#### NODE_ENV (Opcional, mas recomendado)

- **Key**: `NODE_ENV`
- **Value**: `production`

### 4. Verificar Network Access no MongoDB Atlas

**CRÍTICO**: O MongoDB Atlas precisa permitir conexões do Render!

1. No MongoDB Atlas, vá em **Network Access**
2. Clique em **Add IP Address**
3. Clique em **Allow Access from Anywhere** (0.0.0.0/0)
   - Ou adicione os IPs específicos do Render (menos seguro, mas mais restritivo)

### 5. Reiniciar o Serviço

Após adicionar as variáveis:

1. No Render, vá para o seu serviço
2. Clique em **Manual Deploy** → **Deploy latest commit**
   - Ou simplesmente aguarde o auto-deploy se tiver configurado

### 6. Verificar os Logs

1. No Render, vá para **Logs**
2. Você deve ver:
   ```
   🔌 Conectando ao MongoDB...
   ✅ MongoDB Connected: cluster0.xxxxx.mongodb.net
   📊 Database: fincal
   Server running on port 10000
   ```

## ❌ Troubleshooting

### Erro: "MONGODB_URI não está definida"

**Solução**: Verifique se a variável foi adicionada corretamente no Render e se o serviço foi reiniciado.

### Erro: "connect ECONNREFUSED"

**Possíveis causas:**
1. A variável `MONGODB_URI` não está configurada
2. A connection string está incorreta
3. O IP do Render não está permitido no MongoDB Atlas

**Solução:**
1. Verifique se a variável está no Render (Environment)
2. Verifique se a connection string está correta (com senha substituída)
3. No MongoDB Atlas, vá em Network Access e permita 0.0.0.0/0

### Erro: "Authentication failed"

**Solução**: 
1. Verifique se a senha na connection string está correta
2. Verifique se o usuário do banco existe e tem permissões

## ✅ Checklist

- [ ] Variável `MONGODB_URI` configurada no Render
- [ ] Connection string do MongoDB Atlas está correta (com senha)
- [ ] Nome do banco (`fincal`) está na connection string
- [ ] Network Access no MongoDB Atlas permite 0.0.0.0/0
- [ ] Variáveis `SUPABASE_URL` e `SUPABASE_ANON_KEY` configuradas
- [ ] Serviço reiniciado após adicionar variáveis
- [ ] Logs mostram conexão bem-sucedida

