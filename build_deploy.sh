#!/bin/bash

# Script para build e deploy da aplicação
# Uso: ./build_deploy.sh [backend_url]

set -e

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Iniciando build e deploy...${NC}"

# Verificar se a URL do backend foi fornecida
if [ -z "$1" ]; then
    echo -e "${YELLOW}⚠️  URL do backend não fornecida${NC}"
    echo "Uso: ./build_deploy.sh https://seu-backend.onrender.com"
    echo ""
    echo "Deseja continuar com a URL padrão do api_config.dart? (s/n)"
    read -r response
    if [[ ! "$response" =~ ^[Ss]$ ]]; then
        echo "Cancelado."
        exit 1
    fi
    BACKEND_URL=""
else
    BACKEND_URL="$1"
    echo -e "${GREEN}✓ URL do backend: ${BACKEND_URL}${NC}"
fi

# Atualizar api_config.dart se URL foi fornecida
if [ ! -z "$BACKEND_URL" ]; then
    echo -e "${YELLOW}📝 Atualizando api_config.dart...${NC}"
    # Remove trailing slash se houver
    BACKEND_URL=$(echo "$BACKEND_URL" | sed 's:/*$::')
    # Adiciona /api se não tiver
    if [[ ! "$BACKEND_URL" == *"/api" ]]; then
        BACKEND_URL="${BACKEND_URL}/api"
    fi
    
    # Atualiza o arquivo
    sed -i.bak "s|static const String productionBaseUrl = '.*';|static const String productionBaseUrl = '${BACKEND_URL}';|" lib/config/api_config.dart
    rm -f lib/config/api_config.dart.bak
    echo -e "${GREEN}✓ api_config.dart atualizado${NC}"
fi

# Build do Flutter
echo -e "${YELLOW}🔨 Fazendo build do Flutter...${NC}"
if [ ! -z "$BACKEND_URL" ]; then
    flutter build web --dart-define=API_BASE_URL="${BACKEND_URL}" --release
else
    flutter build web --release
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build concluído com sucesso!${NC}"
else
    echo -e "${RED}✗ Erro no build${NC}"
    exit 1
fi

# Deploy no Firebase
echo -e "${YELLOW}🔥 Fazendo deploy no Firebase...${NC}"
firebase deploy --only hosting

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Deploy concluído com sucesso!${NC}"
    echo ""
    echo -e "${GREEN}🎉 Aplicação disponível em: https://seu-projeto.firebaseapp.com${NC}"
else
    echo -e "${RED}✗ Erro no deploy${NC}"
    exit 1
fi

