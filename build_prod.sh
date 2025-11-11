#!/bin/bash

# Script para fazer build de produção e deploy no Firebase
# Lê as credenciais do arquivo .env na raiz do projeto
# 
# USO:
# 1. Crie um arquivo .env na raiz do projeto com:
#    SUPABASE_URL=https://seu-projeto.supabase.co
#    SUPABASE_ANON_KEY=sua-chave-anon-aqui
# 2. Execute: chmod +x build_prod.sh
# 3. Execute: ./build_prod.sh

set -e

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Iniciando build e deploy...${NC}"

# Verificar se o arquivo .env existe
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Arquivo .env não encontrado!${NC}"
    echo ""
    echo "Crie um arquivo .env na raiz do projeto com:"
    echo "SUPABASE_URL=https://seu-projeto.supabase.co"
    echo "SUPABASE_ANON_KEY=sua-chave-anon-aqui"
    exit 1
fi

# Carregar variáveis do arquivo .env
echo -e "${YELLOW}📖 Carregando variáveis do arquivo .env...${NC}"

# Função para ler variável do .env (ignora comentários e linhas vazias)
load_env_var() {
    local var_name=$1
    local value=$(grep -E "^${var_name}=" "$ENV_FILE" | cut -d '=' -f2- | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//" | xargs)
    echo "$value"
}

SUPABASE_URL=$(load_env_var "SUPABASE_URL")
SUPABASE_ANON_KEY=$(load_env_var "SUPABASE_ANON_KEY")

# Verificar se as variáveis foram carregadas
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo -e "${RED}❌ Erro: SUPABASE_URL ou SUPABASE_ANON_KEY não encontradas no arquivo .env${NC}"
    echo ""
    echo "Certifique-se de que o arquivo .env contém:"
    echo "SUPABASE_URL=https://seu-projeto.supabase.co"
    echo "SUPABASE_ANON_KEY=sua-chave-anon-aqui"
    exit 1
fi

echo -e "${GREEN}✓ Credenciais carregadas do .env${NC}"
echo -e "${YELLOW}  URL: ${SUPABASE_URL:0:30}...${NC}"

# Limpar build anterior (opcional, descomente se necessário)
# echo -e "${YELLOW}🧹 Limpando build anterior...${NC}"
# flutter clean

# Obter dependências
echo -e "${YELLOW}📦 Obtendo dependências...${NC}"
flutter pub get

# Build para produção
echo -e "${YELLOW}🔨 Fazendo build para produção...${NC}"
flutter build web \
  --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build concluído com sucesso!${NC}"
else
    echo -e "${RED}❌ Erro no build${NC}"
    exit 1
fi

# Verificar se os arquivos essenciais existem
echo -e "${YELLOW}🔍 Verificando arquivos essenciais...${NC}"

ESSENTIAL_FILES=(
  "build/web/index.html"
  "build/web/main.dart.js"
  "build/web/flutter.js"
)

MISSING_FILES=()

for file in "${ESSENTIAL_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo -e "${GREEN}✓ $file${NC}"
  else
    echo -e "${RED}✗ $file (FALTANDO!)${NC}"
    MISSING_FILES+=("$file")
  fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
  echo ""
  echo -e "${RED}❌ Alguns arquivos essenciais estão faltando!${NC}"
  exit 1
fi

# Deploy no Firebase
echo ""
echo -e "${YELLOW}🔥 Fazendo deploy no Firebase...${NC}"
firebase deploy --only hosting

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Deploy concluído com sucesso!${NC}"
    echo ""
    echo -e "${GREEN}🎉 Aplicação disponível no Firebase Hosting!${NC}"
else
    echo -e "${RED}❌ Erro no deploy${NC}"
    exit 1
fi

