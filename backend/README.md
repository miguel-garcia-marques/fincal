# FinCal Backend API

Backend Node.js com Express e MongoDB para a aplicação FinCal de gestão financeira.

## Pré-requisitos

- Node.js (v14 ou superior)
- MongoDB (local ou MongoDB Atlas)

## Instalação

1. Instalar dependências:
```bash
cd backend
npm install
```

2. Configurar variáveis de ambiente:
```bash
cp .env.example .env
```

Editar o ficheiro `.env` e configurar:
- `PORT`: Porta do servidor (padrão: 3000)
- `MONGODB_URI`: URI de conexão do MongoDB

### MongoDB Local
```env
MONGODB_URI=mongodb://localhost:27017/finance_management
```

### MongoDB Atlas
```env
MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/finance_management?retryWrites=true&w=majority
```

## Executar

### Modo desenvolvimento (com nodemon):
```bash
npm run dev
```

### Modo produção:
```bash
npm start
```

O servidor estará disponível em `http://localhost:3000`

## API Endpoints

### GET /api/transactions
Obter todas as transações

**Resposta:**
```json
[
  {
    "_id": "...",
    "id": "1234567890",
    "type": "ganho",
    "date": "2025-01-15T00:00:00.000Z",
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
]
```

### GET /api/transactions/range?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD
Obter transações em um período específico (inclui transações periódicas geradas)

**Parâmetros:**
- `startDate`: Data inicial (formato: YYYY-MM-DD)
- `endDate`: Data final (formato: YYYY-MM-DD)

**Exemplo:**
```
GET /api/transactions/range?startDate=2025-01-01&endDate=2025-01-31
```

### POST /api/transactions
Criar nova transação

**Body:**
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
Atualizar transação existente

### DELETE /api/transactions/:id
Deletar transação

## Estrutura do Projeto

```
backend/
├── config/
│   └── database.js          # Configuração MongoDB
├── models/
│   └── Transaction.js        # Modelo de transação
├── routes/
│   └── transactions.js       # Rotas da API
├── utils/
│   └── zeller.js            # Fórmula de Zeller
├── server.js                # Servidor Express
├── package.json
└── README.md
```

## Notas

- As transações periódicas (semanais e mensais) são geradas automaticamente quando consultadas via `/range`
- O ID da transação deve ser único (gerado no cliente)
- As percentagens do salário devem somar exatamente 100%
- Despesas devem ter uma categoria de orçamento (gastos, lazer, poupança)

