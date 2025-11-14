# Configuração do Firebase AI Logic (Gemini) para Extração de Faturas

Este guia explica como configurar o Firebase AI Logic (Gemini) para extrair informações de faturas usando IA.

## Pré-requisitos

1. Conta no Google Cloud Platform (GCP)
2. Projeto Firebase configurado
3. API do Gemini habilitada

## Passo 1: Obter Chave da API do Gemini

1. Acesse [Google AI Studio](https://aistudio.google.com/)
2. Faça login com sua conta Google
3. Clique em "Get API Key" ou acesse diretamente [aqui](https://aistudio.google.com/app/apikey)
4. Selecione ou crie um projeto do Google Cloud
5. Copie a chave da API gerada

## Passo 2: Configurar Variável de Ambiente no Backend

### Desenvolvimento Local

1. No arquivo `.env` do backend, adicione:
```env
GEMINI_API_KEY=sua-chave-api-aqui
```

### Produção (Render)

1. Acesse o painel do Render
2. Vá em **Environment**
3. Adicione a variável:
   - **Key**: `GEMINI_API_KEY`
   - **Value**: A chave da API que você copiou do Google AI Studio

## Passo 3: Verificar Configuração

Após configurar a variável de ambiente, reinicie o servidor backend. O endpoint `/api/transactions/extract-from-image` estará disponível.

## Como Funciona

1. O usuário tira uma foto ou seleciona uma imagem da fatura
2. A imagem é enviada para o backend em base64
3. O backend usa a API Gemini para analisar a imagem
4. A IA extrai:
   - Valor da fatura
   - Categoria (compras, café, combustível, etc.)
   - Descrição da transação
   - Data (se visível)
   - Nome do estabelecimento (se visível)
5. Os dados são retornados e preenchem automaticamente o formulário de transação

## Categorias Suportadas

A IA mapeia automaticamente para as seguintes categorias:
- `compras` - Supermercado, loja de conveniência
- `cafe` - Café, pastelaria
- `combustivel` - Posto de gasolina
- `subscricao` - Serviços de assinatura
- `saude` - Farmácia, clínica
- `comerFora` - Restaurante, fast food
- `comprasOnline` - Compras online
- `comprasRoupa` - Loja de roupas
- `comunicacoes` - Telefone, internet
- `miscelaneos` - Outros

## Modelos Utilizados (GRATUITOS)

**IMPORTANTE:** Esta implementação usa APENAS modelos do tier gratuito:

- `gemini-1.5-flash` - Modelo gratuito rápido e eficiente com suporte a análise de imagens
- `gemini-pro-vision` - Modelo legado gratuito com suporte a visão computacional

**Nenhum modelo "Pro" pago é usado.** Todos os modelos na lista são gratuitos e suportam análise de imagens.

## Limites e Custos

- ✅ **100% GRATUITO** - A implementação usa apenas modelos do tier gratuito
- A API Gemini tem limites de uso gratuitos generosos (15 RPM, 1M TPM)
- Não é necessário cartão de crédito para usar os modelos gratuitos
- Consulte a [documentação oficial](https://ai.google.dev/pricing) para informações sobre limites
- O modelo principal usado é `gemini-1.5-flash`, que é rápido, gratuito e suporta análise de imagens

## Troubleshooting

### Erro: "GEMINI_API_KEY não configurada"
- Verifique se a variável de ambiente está configurada corretamente
- Reinicie o servidor após adicionar a variável

### Erro: "Erro na API Gemini"
- Verifique se a chave da API é válida
- Verifique se a API do Gemini está habilitada no seu projeto Google Cloud
- Verifique os limites de uso da API

### Imagem não processada corretamente
- Certifique-se de que a imagem está nítida e bem iluminada
- Tente tirar a foto novamente com melhor iluminação
- Verifique se a fatura está completa e visível na foto

## Segurança

- A chave da API nunca deve ser commitada no repositório
- Use variáveis de ambiente para armazenar a chave
- Configure limites de uso na API do Google Cloud para evitar custos inesperados

