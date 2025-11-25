# FinCal - Finance Management App

Uma aplicação web moderna de gestão financeira construída com Flutter e backend Node.js + MongoDB.

## ✨ Características

- **🔐 Autenticação Robusta**:
    - Login com Supabase Auth (Email/Password)
    - **Passkeys**: Login biométrico sem senha (TouchID/FaceID)
    - Verificação de Email
- **🤖 IA Financeira**:
    - **Extração de Faturas**: Tire uma foto da fatura e a IA (Gemini) extrai valor, data e categoria automaticamente.
- **💰 Gestão Financeira**:
    - **Calendário Inteligente**: Visualização mensal com cálculo de saldo diário.
    - **Gestão de Salário**: Distribuição automática em Gastos (50%), Lazer (30%) e Poupança (20%).
    - **Transações Periódicas**: Suporte a transações únicas, semanais e mensais.
- **👤 Perfil de Usuário**:
    - Foto de perfil com upload e redimensionamento automático.
    - Multi-usuário: Cada usuário tem sua própria collection no MongoDB.
- **📱 Experiência Nativa**:
    - PWA com suporte a instalação no iOS/Android.
    - Universal Links para abrir convites diretamente no app.

## 🛠️ Tech Stack

- **Frontend**: Flutter (Web & Mobile)
- **Backend**: Node.js, Express
- **Database**: MongoDB (Dados do usuário), Supabase (Auth & Storage)
- **AI**: Google Gemini Flash 1.5

## 🚀 Configuração e Setup

### Pré-requisitos
- Flutter SDK (3.0.0+)
- Node.js (v14+)
- MongoDB (Local ou Atlas)
- Conta Supabase

### 1. Variáveis de Ambiente (.env)

Crie um arquivo `.env` no diretório `backend/` com as seguintes variáveis:

```env
# Servidor
PORT=3000

# Banco de Dados
MONGODB_URI=mongodb://localhost:27017/fincal
# Para Atlas: mongodb+srv://user:pass@cluster.mongodb.net/fincal?retryWrites=true&w=majority

# Supabase (Auth & Storage)
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_ANON_KEY=sua-chave-anon-publica
SUPABASE_SERVICE_ROLE_KEY=sua-chave-service-role-secreta # Necessário para deletar usuários
SUPABASE_JWT_SECRET=seu-legacy-jwt-secret # Necessário para Passkeys (Settings -> API -> JWT Settings)

# Passkeys (WebAuthn)
# Dev: localhost | Prod: seu-app.web.app (sem https://)
RP_ID=localhost 
# Dev: http://localhost:8080 | Prod: https://seu-app.web.app
ORIGIN=http://localhost:8080 

# AI (Google Gemini)
GEMINI_API_KEY=sua-chave-api-gemini
```

### 2. Configuração do Supabase

1.  **Auth**: Habilite Email/Password em *Authentication > Providers*.
2.  **Storage**: Crie um bucket público chamado `profile-pictures`. Configure as políticas RLS:
    *   SELECT: Public
    *   INSERT/UPDATE/DELETE: Authenticated users (apenas na própria pasta)
3.  **Email Templates**: Configure o template de confirmação em *Authentication > Email Templates*.
4.  **Redirect URLs**: Adicione a URL de produção (ex: `https://fincal-f7.web.app`) em *Authentication > URL Configuration*.

## 💻 Desenvolvimento

### Instalação

```bash
# Frontend
flutter pub get

# Backend
cd backend
npm install
```

### Executar Localmente

1.  **Backend**:
    ```bash
    cd backend
    npm run dev
    ```
2.  **Frontend**:
    ```bash
    flutter run -d chrome
    # Ou com variáveis de ambiente específicas
    flutter run -d chrome --dart-define=SUPABASE_URL=...
    ```

### Ícones e PWA
Os ícones estão em `web/icons/`. Para atualizar, substitua os arquivos e rode `flutter build web`.
Para suporte a Universal Links no iOS (abrir app via QR Code), o arquivo `apple-app-site-association` já está configurado.

## 📦 Deploy

Use o script automatizado para deploy no Firebase Hosting:

```bash
./build_prod.sh
```
Este script carrega as variáveis do `.env`, faz o build (`flutter build web --release`) e deploy (`firebase deploy`).

## 🔐 Segurança

- **Tokens**:
    - Mobile: Armazenados seguramente (Keychain/EncryptedSharedPreferences).
    - Web: `localStorage` (com expiração de 1h e Refresh Tokens automáticos).
- **Passkeys**: Implementação segura usando WebAuthn. O backend gera tokens JWT manualmente usando `SUPABASE_JWT_SECRET` para permitir login sem senha.
- **Proteção**:
    - Rate Limiting em rotas de auth.
    - Sanitização de inputs contra XSS.
    - Headers de segurança (HSTS, NoSniff) configurados no `firebase.json`.

## 📱 Fluxos de Navegação

### Fluxo de Autenticação e Onboarding

```mermaid
flowchart TD
    Start([App Iniciado]) --> AuthCheck{Usuário<br/>Autenticado?}
    
    AuthCheck -->|Não| Login[Login Screen]
    Login --> LoginMethod{Método de<br/>Login}
    LoginMethod -->|Email/Password| EmailLogin[Login com Email]
    LoginMethod -->|Passkey| PasskeyLogin[Login com Passkey]
    LoginMethod -->|Registro| SignUp[Registro de Novo Usuário]
    
    SignUp --> EmailVerif[Email Verification Screen]
    EmailLogin --> EmailCheck{Email<br/>Verificado?}
    EmailCheck -->|Não| EmailVerif
    EmailCheck -->|Sim| ProfileCheck
    
    EmailVerif -->|Email Confirmado| ProfileCheck{Tem Foto<br/>de Perfil?}
    PasskeyLogin --> PasskeyVerif[Passkey Verification Screen]
    PasskeyVerif -->|Autenticado| ProfileCheck
    
    ProfileCheck -->|Não| ProfilePic[Profile Picture Selection Screen]
    ProfileCheck -->|Sim| WalletCheck{Tem Wallet<br/>Selecionada?}
    
    ProfilePic -->|Foto Selecionada/Pulada| WalletCheck
    
    WalletCheck -->|Não| WalletSelect[Wallet Selection Screen]
    WalletCheck -->|Sim| Home[Home Screen]
    WalletSelect -->|Wallet Selecionada| Home
    
    AuthCheck -->|Sim| OnboardingCheck{Onboarding<br/>Completo?}
    OnboardingCheck -->|Não| ProfileCheck
    OnboardingCheck -->|Sim| Home
    
    style Start fill:#e1f5ff
    style Home fill:#c8e6c9
    style Login fill:#fff9c4
    style EmailVerif fill:#ffe0b2
    style PasskeyVerif fill:#ffe0b2
```

### Fluxo de Convites (Invite Flow)

```mermaid
flowchart TD
    InviteLink([Link de Convite Recebido]) --> AuthCheck{Usuário<br/>Autenticado?}
    
    AuthCheck -->|Não| LoginInvite[Login Screen<br/>com Token de Convite]
    LoginInvite --> LoginComplete{Login<br/>Completo?}
    LoginComplete -->|Sim| InviteAccept
    LoginComplete -->|Não| LoginInvite
    
    AuthCheck -->|Sim| InviteAccept[Invite Accept Screen]
    
    InviteAccept --> InviteAction{Ação do<br/>Usuário}
    InviteAction -->|Aceitar| CreateAccount[Criar Conta na Wallet]
    InviteAction -->|Recusar| Home[Home Screen]
    
    CreateAccount --> Home
    
    style InviteLink fill:#e1f5ff
    style InviteAccept fill:#fff9c4
    style Home fill:#c8e6c9
```

### Fluxo Principal da Aplicação (Home Screen)

```mermaid
flowchart TD
    Home[Home Screen] --> HomeActions{Ação do<br/>Usuário}
    
    HomeActions -->|Ver Calendário| Calendar[Visualização do Calendário]
    HomeActions -->|Ver Transações| TransList[Lista de Transações]
    HomeActions -->|Adicionar Transação| AddTx[Add Transaction Screen]
    HomeActions -->|Configurações| Settings[Settings Menu Screen]
    HomeActions -->|Perfil| Profile[Profile Screen]
    
    Calendar -->|Clicar em Dia| DayDetails[Day Details Screen]
    DayDetails -->|Ver Transação| TxDetails[Transaction Details Screen]
    DayDetails -->|Editar Transação| AddTx
    
    TransList -->|Clicar em Transação| TxDetails
    
    TxDetails -->|Editar| AddTx
    TxDetails -->|Voltar| Home
    
    AddTx -->|Salvar| Home
    AddTx -->|Cancelar| Home
    
    Settings -->|Segurança| Security[Security Screen]
    Settings -->|Configurações Gerais| SettingsGen[Settings Screen]
    Settings -->|Convites de Wallet| WalletInvites[Wallet Invites Screen]
    Settings -->|Voltar| Home
    
    Security -->|Voltar| Settings
    SettingsGen -->|Voltar| Settings
    WalletInvites -->|Voltar| Settings
    
    Profile -->|Voltar| Home
    
    style Home fill:#c8e6c9
    style AddTx fill:#fff9c4
    style TxDetails fill:#e1f5ff
    style DayDetails fill:#e1f5ff
```

### Estados de Bloqueio e Segurança

```mermaid
flowchart TD
    AppActive[App Ativo] --> FocusLost{App Perde<br/>Foco?}
    
    FocusLost -->|Sim| Locked[App Lock Screen]
    FocusLost -->|Não| AppActive
    
    Locked --> UserAction{Usuário<br/>Interage?}
    UserAction -->|Desbloquear| SessionCheck{Sessão<br/>Válida?}
    
    SessionCheck -->|Sim| AppActive
    SessionCheck -->|Não| Logout[Logout Automático]
    Logout --> Login[Login Screen]
    
    Login --> AppActive
    
    style AppActive fill:#c8e6c9
    style Locked fill:#ffcdd2
    style Login fill:#fff9c4
```

## 🐛 Troubleshooting

### Passkeys pedindo senha?
Verifique se `SUPABASE_JWT_SECRET` está configurado no backend. Sem ele, o backend não consegue gerar a sessão automaticamente e faz fallback para senha.

### Email de verificação não chega?
1.  Verifique se "Enable email confirmations" está ON no Supabase.
2.  Configure um SMTP customizado (Resend, SendGrid) para produção, pois o SMTP padrão do Supabase tem limite baixo (4/hora).

### Tela branca no deploy?
1.  Verifique o console do navegador (F12) por erros JS ou 404.
2.  Certifique-se de que o build foi feito com `--release`.
3.  Verifique se as variáveis de ambiente (Supabase URL/Key) foram injetadas corretamente durante o build.

### Erro de CORS?
Verifique se o domínio do frontend (ex: `https://fincal-f7.web.app`) está na lista de `allowedOrigins` no `backend/server.js`.

---
*Projeto de uso pessoal.*
