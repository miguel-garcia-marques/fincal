# Instruções de Deploy

## 🚀 Deploy Rápido com Script Automatizado

O script `build_prod.sh` automatiza todo o processo de build e deploy no Firebase.

### Passo 1: Criar arquivo .env

Na raiz do projeto, crie um arquivo `.env` com suas credenciais:

```bash
cp .env.example .env
```

Edite o arquivo `.env` e adicione suas credenciais reais:

```env
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_ANON_KEY=sua-chave-anon-aqui
```

### Passo 2: Executar o script

```bash
chmod +x build_prod.sh
./build_prod.sh
```

O script irá:
1. ✅ Verificar se o arquivo `.env` existe
2. ✅ Carregar as credenciais do `.env`
3. ✅ Obter dependências do Flutter
4. ✅ Fazer build para produção com as credenciais
5. ✅ Verificar arquivos essenciais
6. ✅ Fazer deploy no Firebase Hosting

## 📋 O que o script faz

1. **Carrega variáveis do .env** - Lê `SUPABASE_URL` e `SUPABASE_ANON_KEY`
2. **Build do Flutter** - Compila a aplicação web com as credenciais
3. **Verificação** - Confirma que todos os arquivos essenciais foram gerados
4. **Deploy no Firebase** - Faz upload para o Firebase Hosting

## 🔐 Segurança

- O arquivo `.env` está no `.gitignore` e **NÃO será commitado**
- Use o arquivo `.env.example` como template
- **NUNCA** commite o arquivo `.env` com credenciais reais

## ⚠️ Requisitos

- Flutter instalado e configurado
- Firebase CLI instalado (`npm install -g firebase-tools`)
- Projeto Firebase inicializado (`firebase init`)
- Arquivo `.env` criado com as credenciais

## 🐛 Troubleshooting

### Erro: "Arquivo .env não encontrado"
- Certifique-se de que o arquivo `.env` está na raiz do projeto
- Use `cp .env.example .env` para criar o arquivo

### Erro: "SUPABASE_URL ou SUPABASE_ANON_KEY não encontradas"
- Verifique se as variáveis estão no formato correto no `.env`
- Não use aspas ao redor dos valores (a menos que façam parte do valor)
- Certifique-se de que não há espaços antes ou depois do `=`

### Erro no deploy do Firebase
- Verifique se está logado: `firebase login`
- Verifique se o projeto Firebase está inicializado: `firebase init`
- Verifique se tem permissões no projeto Firebase

## 📝 Exemplo de arquivo .env

```env
SUPABASE_URL=https://fjuedycchyiynyqivkch.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## 🔄 Deploy Manual (sem script)

Se preferir fazer manualmente:

```bash
# 1. Carregar variáveis do .env
export $(cat .env | xargs)

# 2. Build
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

# 3. Deploy
firebase deploy --only hosting
```

