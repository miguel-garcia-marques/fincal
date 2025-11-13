# Como Obter e Configurar a SUPABASE_SERVICE_ROLE_KEY

## 🔑 O que é a Service Role Key?

A **Service Role Key** é uma chave de API do Supabase com permissões administrativas completas. Ela é necessária para:
- Deletar usuários do Supabase Auth via Admin API
- Realizar operações administrativas no Supabase
- Acessar recursos que a anon key não pode acessar

⚠️ **IMPORTANTE**: Esta chave é **SECRETA** e nunca deve ser exposta no frontend ou em código público!

## 📍 Onde Encontrar no Supabase

### Passo 1: Acessar o Dashboard
1. Acesse [https://app.supabase.com](https://app.supabase.com)
2. Faça login na sua conta
3. Selecione o seu projeto

### Passo 2: Navegar para Settings → API
1. No menu lateral esquerdo, clique em **Settings** (⚙️)
2. Clique em **API** no submenu

### Passo 3: Encontrar a Service Role Key
1. Role a página até encontrar a seção **Project API keys**
2. Você verá duas chaves:
   - **anon public** - Esta é a chave pública (já configurada como `SUPABASE_ANON_KEY`)
   - **service_role secret** - Esta é a chave que você precisa! 🔑

3. Clique no ícone de **olho** ou **copiar** ao lado de **service_role secret**
4. **Copie a chave completa** (ela é bem longa)

## 🔧 Como Configurar no Render

### Opção 1: Via Painel do Render (Recomendado)

1. Acesse [https://dashboard.render.com](https://dashboard.render.com)
2. Faça login e selecione seu serviço (`finance-management-backend`)
3. No menu lateral, clique em **Environment**
4. Clique em **Add Environment Variable**
5. Configure:
   - **Key**: `SUPABASE_SERVICE_ROLE_KEY`
   - **Value**: Cole a chave que você copiou do Supabase
6. Clique em **Save Changes**
7. O serviço será reiniciado automaticamente

### Opção 2: Via render.yaml (Não Recomendado)

⚠️ **ATENÇÃO**: Não coloque a Service Role Key diretamente no `render.yaml` se o arquivo estiver em um repositório público!

Se quiser usar o `render.yaml`, você pode adicionar:

```yaml
envVars:
  - key: SUPABASE_SERVICE_ROLE_KEY
    sync: false  # Será configurado manualmente no painel do Render
```

E depois configurar manualmente no painel do Render (Opção 1).

## ✅ Verificação

Após configurar, você pode verificar se está funcionando:

1. No Render, vá para **Logs**
2. Tente deletar uma conta de teste
3. Se funcionar, você verá nos logs que o usuário foi deletado do Supabase Auth

## 🔒 Segurança

- ✅ **NUNCA** commite a Service Role Key no Git
- ✅ **NUNCA** exponha no frontend
- ✅ **SOMENTE** use no backend
- ✅ Mantenha segura e não compartilhe
- ✅ Se suspeitar que foi exposta, gere uma nova chave no Supabase

## 🆘 Troubleshooting

### Erro: "Erro ao deletar usuário do Supabase Auth"

**Possíveis causas:**
1. A `SUPABASE_SERVICE_ROLE_KEY` não está configurada no Render
2. A chave está incorreta
3. O serviço não foi reiniciado após adicionar a variável

**Solução:**
1. Verifique se a variável está configurada no Render (Environment)
2. Verifique se copiou a chave completa (sem espaços extras)
3. Reinicie o serviço no Render
4. Verifique os logs para ver o erro específico

### Como Gerar uma Nova Service Role Key

Se precisar gerar uma nova chave:
1. No Supabase Dashboard → Settings → API
2. Role até **Project API keys**
3. Clique em **Reset** ao lado de **service_role secret**
4. Confirme a ação
5. Uma nova chave será gerada
6. Atualize no Render com a nova chave

## 📝 Resumo Rápido

1. **Onde encontrar**: Supabase Dashboard → Settings → API → service_role secret
2. **Onde configurar**: Render Dashboard → Seu Serviço → Environment → Add Variable
3. **Nome da variável**: `SUPABASE_SERVICE_ROLE_KEY`
4. **Valor**: A chave service_role que você copiou do Supabase

