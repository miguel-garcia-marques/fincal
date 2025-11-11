#!/bin/bash

# Script para rebuild completo e deploy
# Use este script se estiver tendo problemas com tela branca

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🧹 Limpando build anterior...${NC}"
flutter clean

echo -e "${GREEN}📦 Obtendo dependências...${NC}"
flutter pub get

echo -e "${YELLOW}🔨 Fazendo build para web (release)...${NC}"
flutter build web --release

echo -e "${GREEN}✓ Build concluído!${NC}"
echo ""

# Verificar se os arquivos essenciais existem
echo -e "${YELLOW}🔍 Verificando arquivos essenciais...${NC}"

ESSENTIAL_FILES=(
  "build/web/index.html"
  "build/web/main.dart.js"
  "build/web/flutter.js"
  "build/web/flutter_bootstrap.js"
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
  echo "O build pode ter falhado. Verifique os erros acima."
  exit 1
fi

echo ""
echo -e "${GREEN}✅ Todos os arquivos essenciais estão presentes!${NC}"
echo ""

# Perguntar se quer fazer deploy
read -p "Deseja fazer deploy no Firebase agora? (s/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
  echo -e "${YELLOW}🔥 Fazendo deploy no Firebase...${NC}"
  firebase deploy --only hosting
  
  if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Deploy concluído com sucesso!${NC}"
    echo ""
    echo -e "${YELLOW}📝 Próximos passos:${NC}"
    echo "1. Acesse a URL do Firebase"
    echo "2. Abra o Console do navegador (F12)"
    echo "3. Verifique se há erros"
    echo "4. Se ainda houver tela branca, consulte TROUBLESHOOTING.md"
  else
    echo -e "${RED}❌ Erro no deploy${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}Build concluído. Execute 'firebase deploy --only hosting' quando estiver pronto.${NC}"
fi

