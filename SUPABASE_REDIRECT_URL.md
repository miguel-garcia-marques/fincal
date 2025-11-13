# Configuração de URL de Redirecionamento no Supabase

## 🔍 Problema

Quando você clica no link de confirmação de email do Supabase, ele redireciona para `localhost` em vez da URL de produção da sua app.

## ✅ Solução

O problema está na configuração do **Supabase Dashboard**. Você precisa configurar a URL de redirecionamento correta lá.

### Passo 1: Acessar Configurações do Supabase

1. Acesse [Supabase Dashboard](https://app.supabase.com)
2. Selecione seu projeto
3. Vá em **Settings** (Configurações) → **Auth** (Autenticação)

### Passo 2: Configurar Site URL

Na seção **Site URL**, configure a URL de produção da sua app:

```
https://seu-projeto.web.app
```

ou

```
https://seu-dominio.com
```

**Importante**: Esta é a URL base da sua aplicação no Firebase Hosting.

### Passo 3: Configurar Redirect URLs

Na seção **Redirect URLs**, adicione todas as URLs que podem receber redirecionamentos:

```
https://seu-projeto.web.app
https://seu-projeto.firebaseapp.com
https://seu-dominio.com
```

**Para desenvolvimento local** (opcional, apenas se quiser testar localmente):

```
http://localhost:8080
http://localhost:3000
http://127.0.0.1:8080
```

### Passo 4: Salvar Configurações

Clique em **Save** (Salvar) para aplicar as mudanças.

## 🔧 Como o Código Funciona Agora

O código foi melhorado para:

1. **Em produção (build release)**:
   - Se detectar `localhost`, retorna `null` e deixa o Supabase usar a URL configurada no dashboard
   - Se detectar uma URL de produção (ex: `seu-projeto.web.app`), usa essa URL

2. **Em desenvolvimento**:
   - Usa `localhost` para facilitar testes locais

3. **Prioridade de configuração**:
   - Primeiro: `--dart-define=APP_BASE_URL=...` (se fornecido no build)
   - Segundo: `AppConfig.productionAppUrl` (se configurado)
   - Terceiro: URL atual detectada automaticamente
   - Último: `null` (Supabase usa URL do dashboard)

## 📝 Configurar URL no Build

Você também pode configurar a URL durante o build:

```bash
flutter build web --release \
  --dart-define=APP_BASE_URL=https://seu-projeto.web.app \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

Ou editar `lib/config/app_config.dart`:

```dart
static const String productionAppUrl = 'https://seu-projeto.web.app';
```

## ⚠️ Importante

**O Supabase Dashboard é a fonte de verdade para URLs de redirecionamento!**

Mesmo que o código passe uma URL diferente, o Supabase só aceita URLs que estão na lista de **Redirect URLs** configurada no dashboard.

Por isso, é **essencial** configurar a URL de produção no Supabase Dashboard.

## 🐛 Troubleshooting

### Ainda redireciona para localhost?

1. Verifique se a URL de produção está na lista de **Redirect URLs** no Supabase Dashboard
2. Verifique se a **Site URL** está configurada corretamente
3. Faça um novo build de produção após configurar
4. Limpe o cache do navegador

### Como descobrir a URL do Firebase Hosting?

Após fazer deploy no Firebase:

```bash
firebase deploy --only hosting
```

O Firebase mostrará a URL onde sua app está hospedada, algo como:
- `https://seu-projeto.web.app`
- `https://seu-projeto.firebaseapp.com`

Use essa URL no Supabase Dashboard.

