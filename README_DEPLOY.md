# Guia de Deploy - Finance Management App

Este guia explica como fazer deploy da aplicação completa (backend + frontend) de forma gratuita.

## 🚀 Resumo Rápido

- **Backend**: Render (gratuito) - https://render.com
- **Banco de Dados**: MongoDB Atlas (gratuito até 512MB) - https://www.mongodb.com/cloud/atlas
- **Frontend**: Firebase Hosting (gratuito) - https://firebase.google.com

**Tempo estimado**: 30-45 minutos

## 📋 Índice

1. [Pré-requisitos](#pré-requisitos)
2. [Deploy do Backend (Render)](#deploy-do-backend-render)
3. [Configuração do MongoDB Atlas](#configuração-do-mongodb-atlas)
4. [Deploy do Frontend (Firebase Hosting)](#deploy-do-frontend-firebase-hosting)
5. [Configuração Final](#configuração-final)

---

## Pré-requisitos

- Conta no [Render](https://render.com) (gratuita)
- Conta no [MongoDB Atlas](https://www.mongodb.com/cloud/atlas) (gratuita até 512MB)
- Conta no [Firebase](https://firebase.google.com) (gratuita)
- Git configurado no seu projeto
- Node.js instalado localmente (para testes)

---

## Deploy do Backend (Render)

### 1. Criar Cluster MongoDB no Atlas

1. Acesse [MongoDB Atlas](https://www.mongodb.com/cloud/atlas)
2. Crie uma conta gratuita (se ainda não tiver)
3. Crie um novo cluster (escolha a opção **FREE** - M0)
4. Configure o usuário do banco de dados:
   - Vá em **Database Access** → **Add New Database User**
   - Crie um usuário e senha (guarde essas credenciais!)
5. Configure o acesso à rede:
   - Vá em **Network Access** → **Add IP Address**
   - Clique em **Allow Access from Anywhere** (0.0.0.0/0) para permitir acesso do Render
6. Obtenha a connection string:
   - Vá em **Database** → **Connect** → **Connect your application**
   - Copie a connection string (algo como: `mongodb+srv://user:password@cluster.mongodb.net/`)
   - Substitua `<password>` pela senha do usuário criado
   - Adicione o nome do banco no final: `mongodb+srv://user:password@cluster.mongodb.net/fincal`

### 2. Deploy no Render

1. Acesse [Render](https://render.com) e faça login com GitHub
2. Clique em **New +** → **Web Service**
3. Conecte seu repositório GitHub
4. Configure o serviço:
   - **Name**: `finance-management-backend`
   - **Environment**: `Node`
   - **Build Command**: `cd backend && npm install`
   - **Start Command**: `cd backend && npm start`
   - **Plan**: `Free`

5. Configure as variáveis de ambiente:
   - Clique em **Environment** e adicione:
     ```
     MONGODB_URI=mongodb+srv://user:password@cluster.mongodb.net/fincal
     SUPABASE_URL=https://fjuedycchyiynyqivkch.supabase.co
     SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZqdWVkeWNjaHlpeW55cWl2a2NoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI2MTgwOTIsImV4cCI6MjA3ODE5NDA5Mn0.vIeykvK-puQx8q52AARQY8fLl_7EvzL8Vz7VFANKBNo
     NODE_ENV=production
     ```
   - **IMPORTANTE**: Substitua `MONGODB_URI` pela sua connection string do Atlas

6. Clique em **Create Web Service**
7. Aguarde o deploy (pode levar alguns minutos)
8. Anote a URL do serviço (ex: `https://finance-management-backend.onrender.com`)

### 3. Testar o Backend

Após o deploy, teste acessando:
```
https://seu-backend.onrender.com/
```

Deve retornar um JSON com informações da API.

---

## Deploy do Frontend (Firebase Hosting)

### 1. Instalar Firebase CLI

```bash
npm install -g firebase-tools
```

### 2. Fazer Login no Firebase

```bash
firebase login
```

### 3. Inicializar Firebase no Projeto

```bash
cd "/Users/miguelgarciamarques/Desktop/DEV/Finance Management"
firebase init hosting
```

Escolha:
- **What do you want to use as your public directory?** → `build/web`
- **Configure as a single-page app?** → `Yes`
- **Set up automatic builds and deploys with GitHub?** → `No` (ou `Yes` se quiser CI/CD)

### 4. Configurar URL da API

O projeto já está configurado para usar a URL do backend automaticamente. Você tem duas opções:

**Opção 1: Usar o script de build (Recomendado)**

O script `build_deploy.sh` já está configurado e atualiza automaticamente a URL:

```bash
./build_deploy.sh https://seu-backend.onrender.com
```

**Opção 2: Atualizar manualmente**

1. Edite o arquivo `lib/config/api_config.dart` e atualize a URL:
   ```dart
   static const String productionBaseUrl = 'https://seu-backend.onrender.com/api';
   ```

2. Ou use variável de ambiente no build:
   ```bash
   flutter build web --dart-define=API_BASE_URL=https://seu-backend.onrender.com/api
   ```

### 5. Build e Deploy

**Usando o script (Recomendado):**

```bash
./build_deploy.sh https://seu-backend.onrender.com
```

**Ou manualmente:**

```bash
# Build da aplicação Flutter
flutter build web --dart-define=API_BASE_URL=https://seu-backend.onrender.com/api

# Deploy no Firebase
firebase deploy --only hosting
```

### 6. Acessar a Aplicação

Após o deploy, você receberá uma URL como:
```
https://seu-projeto.firebaseapp.com
```

---

## Configuração Final

### 1. Atualizar CORS no Backend (se necessário)

O backend já está configurado com `cors()`, mas se tiver problemas, você pode restringir para o domínio do Firebase:

No arquivo `backend/server.js`, você pode atualizar:

```javascript
const cors = require('cors');

const corsOptions = {
  origin: [
    'http://localhost:3000',
    'https://seu-projeto.firebaseapp.com',
    'https://seu-projeto.web.app'
  ],
  credentials: true
};

app.use(cors(corsOptions));
```

### 2. Verificar Variáveis de Ambiente

Certifique-se de que todas as variáveis de ambiente estão configuradas corretamente no Render:
- `MONGODB_URI`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `NODE_ENV=production`

### 3. Testar a Aplicação Completa

1. Acesse a URL do Firebase
2. Faça login
3. Teste criar uma transação
4. Verifique se os dados estão sendo salvos no MongoDB Atlas

---

## Troubleshooting

### Backend não inicia no Render

- Verifique os logs no painel do Render
- Confirme que todas as variáveis de ambiente estão configuradas
- Verifique se a connection string do MongoDB está correta

### Erro de CORS

- Adicione o domínio do Firebase nas configurações de CORS do backend
- Verifique se o backend está acessível publicamente

### Frontend não consegue conectar ao backend

- Verifique se a URL da API está correta no build
- Confirme que o backend está rodando (acesse a URL diretamente)
- Verifique os logs do navegador (F12 → Console)

### MongoDB Connection Error

- Verifique se o IP do Render está permitido no MongoDB Atlas
- Confirme que a connection string está correta
- Verifique se o usuário do banco tem permissões adequadas

---

## Alternativas Gratuitas

Se o Render não funcionar para você, aqui estão outras opções gratuitas:

### Backend:
- **Railway** (https://railway.app) - $5 crédito/mês grátis
- **Fly.io** (https://fly.io) - Tier gratuito generoso
- **Cyclic** (https://cyclic.sh) - Gratuito para Node.js

### Frontend:
- **Vercel** (https://vercel.com) - Alternativa ao Firebase
- **Netlify** (https://netlify.com) - Alternativa ao Firebase

---

## Custos

- **Render**: Gratuito (com limitações: pode "dormir" após 15min de inatividade)
- **MongoDB Atlas**: Gratuito até 512MB
- **Firebase Hosting**: Gratuito (10GB storage, 360MB/day transfer)

**Nota**: O tier gratuito do Render pode fazer o serviço "dormir" após inatividade. A primeira requisição após dormir pode levar ~30 segundos para acordar. Para evitar isso, considere usar um serviço de "ping" automático ou upgrade para o plano pago.

---

## Próximos Passos

1. Configurar domínio customizado (opcional)
2. Configurar CI/CD automático
3. Adicionar monitoramento e logs
4. Configurar backup automático do MongoDB

---

## Suporte

Se tiver problemas, verifique:
- Logs do Render (Dashboard → Seu Serviço → Logs)
- Logs do Firebase (Firebase Console → Hosting → Logs)
- Console do navegador (F12)

