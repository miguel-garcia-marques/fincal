# FinCal - Finance Management App

Uma aplicação web moderna de gestão financeira construída com Flutter e backend Node.js + MongoDB.

## Características

- 📅 **Calendário Inteligente**: Visualização mensal com cálculo automático de saldo disponível por dia
- 💰 **Gestão de Transações**: Adicione ganhos e despesas com categorias personalizadas
- 💼 **Gestão de Salário**: Distribuição automática do salário em Gastos, Lazer e Poupança
- 📊 **Análise Financeira**: Visualize resumos mensais de ganhos, despesas e saldo
- 🔄 **Transações Periódicas**: Suporte para transações semanais e mensais
- 🎨 **Design Moderno**: Interface elegante em preto e branco com toques de verde/vermelho para valores
- 📱 **Responsivo**: Adaptável a diferentes tamanhos de ecrã
- 🗄️ **MongoDB**: Base de dados robusta com backend Node.js

## Estrutura do Projeto

```
Finance Management/
├── lib/                    # Código Flutter
│   ├── models/            # Modelos de dados
│   ├── screens/           # Telas da aplicação
│   ├── widgets/           # Componentes reutilizáveis
│   ├── services/          # Serviços (API, Database)
│   ├── theme/             # Tema e estilos
│   └── utils/             # Utilitários
├── backend/               # Backend Node.js
│   ├── config/           # Configurações
│   ├── models/           # Modelos MongoDB
│   ├── routes/           # Rotas da API
│   └── utils/            # Utilitários
└── web/                  # Configuração web
```

## Instalação

### Pré-requisitos

- Flutter SDK (versão 3.0.0 ou superior)
- Node.js (v14 ou superior)
- MongoDB (local ou MongoDB Atlas)

### 1. Instalar Dependências Flutter

```bash
flutter pub get
```

### 2. Configurar Backend

```bash
cd backend
npm install
```

Criar ficheiro `.env`:
```bash
cp .env.example .env
```

Editar `.env` e configurar:
```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/finance_management
```

Para MongoDB Atlas:
```env
MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/finance_management?retryWrites=true&w=majority
```

### 3. Iniciar Backend

```bash
cd backend
npm run dev
```

O servidor estará disponível em `http://localhost:3000`

### 4. Configurar URL da API no Flutter

Editar `lib/services/api_service.dart` e ajustar `baseUrl`:

```dart
static const String baseUrl = 'http://localhost:3000/api';
```

**Nota importante para diferentes ambientes:**
- **Web (Chrome)**: `http://localhost:3000/api`
- **Android Emulator**: `http://10.0.2.2:3000/api`
- **iOS Simulator**: `http://localhost:3000/api`
- **Dispositivo Físico**: `http://SEU_IP_LOCAL:3000/api` (ex: `http://192.168.1.100:3000/api`)

### 5. Executar Aplicação Flutter

```bash
flutter run -d chrome
```

Ou para construir para produção:
```bash
flutter build web
```

## Funcionalidades Detalhadas

### Gestão de Salário

Quando uma transação é marcada como "Ganho" e "É salário?", pode definir percentagens:
- **Gastos**: Percentagem para despesas essenciais
- **Lazer**: Percentagem para entretenimento
- **Poupança**: Percentagem para poupança

As percentagens devem somar 100%. O sistema calcula automaticamente os valores.

### Categorização de Despesas

Todas as despesas devem ser categorizadas em:
- **Gastos**: Despesas essenciais (deduz do orçamento de gastos)
- **Lazer**: Despesas de entretenimento (deduz do orçamento de lazer)
- **Poupança**: Despesas relacionadas a poupança (deduz do orçamento de poupança)

### Transações Periódicas

- **Única**: Transação única (padrão)
- **Semanal**: Repete todas as semanas no dia selecionado
- **Mensal**: Repete todos os meses no dia selecionado

As transações periódicas são geradas automaticamente quando visualiza um período no calendário.

### Visualização no Calendário

O calendário mostra:
- Saldo total disponível
- Valores separados por categoria (G: Gastos, L: Lazer, P: Poupança)
- Indicadores visuais para dias com transações

## API Endpoints

### GET /api/transactions
Obter todas as transações

### GET /api/transactions/range?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD
Obter transações em um período (inclui transações periódicas geradas)

### POST /api/transactions
Criar nova transação

**Body exemplo:**
```json
{
  "id": "1234567890",
  "type": "ganho",
  "date": "2025-01-15",
  "amount": 1400,
  "category": "miscelaneos",
  "isSalary": true,
  "salaryAllocation": {
    "gastosPercent": 50,
    "lazerPercent": 30,
    "poupancaPercent": 20
  },
  "frequency": "unique"
}
```

### PUT /api/transactions/:id
Atualizar transação

### DELETE /api/transactions/:id
Deletar transação

## Tecnologias

### Frontend
- **Flutter**: Framework de UI multiplataforma
- **HTTP**: Cliente HTTP para comunicação com API

### Backend
- **Node.js**: Runtime JavaScript
- **Express**: Framework web
- **MongoDB**: Base de dados NoSQL
- **Mongoose**: ODM para MongoDB

## Modo de Desenvolvimento vs Produção

O serviço `DatabaseService` suporta dois modos:

1. **API Mode** (padrão): Usa MongoDB via API REST
   - Configure `useApi = true` em `lib/services/database.dart`

2. **Local Mode**: Usa SharedPreferences (fallback)
   - Configure `useApi = false` em `lib/services/database.dart`

## Troubleshooting

### Backend não conecta ao MongoDB
- Verifique se o MongoDB está em execução
- Confirme a URI no ficheiro `.env`
- Para MongoDB Atlas, verifique as regras de firewall

### Flutter não consegue conectar à API
- Verifique se o backend está em execução
- Confirme a URL em `api_service.dart`
- Para dispositivos físicos, use o IP local da máquina
- Verifique CORS no backend (já configurado)

### Transações periódicas não aparecem
- Verifique se a transação foi salva com `frequency` correto
- Confirme que o período selecionado inclui as datas esperadas

## Licença

Este projeto é de uso pessoal.
