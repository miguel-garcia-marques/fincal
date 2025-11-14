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

# Função para gerar mensagem de commit usando IA (via Cursor/Claude API)
generate_commit_message_with_ai() {
    # Obter diff completo das mudanças staged
    local diff_content=$(git diff --cached 2>/dev/null)
    
    # Se não houver diff staged, pegar diff não staged
    if [ -z "$diff_content" ]; then
        diff_content=$(git diff 2>/dev/null)
    fi
    
    # Obter lista de arquivos modificados
    local files_changed=$(git diff --cached --name-only 2>/dev/null)
    if [ -z "$files_changed" ]; then
        files_changed=$(git diff --name-only 2>/dev/null)
    fi
    
    # Criar um resumo das mudanças para análise
    local summary="Arquivos modificados:\n"
    summary+="$files_changed\n\n"
    summary+="Diff das mudanças:\n"
    summary+="${diff_content:0:4000}"  # Limitar tamanho para não exceder limites de API
    
    # Tentar usar Cursor AI através de uma chamada de API local
    # Se o Cursor estiver disponível, podemos usar sua API
    # Caso contrário, usar análise inteligente do diff
    
    # Análise inteligente do diff
    local features=()
    local fixes=()
    local refactors=()
    local configs=()
    
    # Analisar arquivos modificados para identificar tipo de mudança
    while IFS= read -r file; do
        if [ -z "$file" ]; then
            continue
        fi
        
        local filename=$(basename "$file")
        
        # Detectar features (novos arquivos em lib/screens ou lib/widgets)
        if [[ "$file" == lib/screens/*.dart ]]; then
            features+=("nova tela: $filename")
        elif [[ "$file" == lib/widgets/*.dart ]]; then
            features+=("novo widget: $filename")
        elif [[ "$file" == lib/services/* ]]; then
            refactors+=("serviço: $filename")
        elif [[ "$file" == backend/routes/* ]]; then
            features+=("endpoint: $filename")
        elif [[ "$file" == backend/models/* ]]; then
            refactors+=("modelo: $filename")
        elif [[ "$file" == *.sh ]] || [[ "$file" == *.bat ]]; then
            configs+=("script: $filename")
        elif [[ "$file" == pubspec.yaml ]] || [[ "$file" == package.json ]]; then
            configs+=("dependências")
        fi
    done <<< "$files_changed"
    
    # Analisar diff para detectar padrões
    if echo "$diff_content" | grep -qiE "(fix|bug|error|corrige|correção)"; then
        fixes+=("correções")
    fi
    
    if echo "$diff_content" | grep -qiE "(add|new|create|novo|adiciona)"; then
        if [ ${#features[@]} -eq 0 ]; then
            features+=("novas funcionalidades")
        fi
    fi
    
    if echo "$diff_content" | grep -qiE "(refactor|clean|improve|melhora|otimiza)"; then
        refactors+=("refatoração")
    fi
    
    # Construir mensagem baseada na análise
    local msg_parts=()
    
    if [ ${#features[@]} -gt 0 ]; then
        local feat_str=$(IFS=", "; echo "${features[*]}")
        msg_parts+=("✨ $feat_str")
    fi
    
    if [ ${#fixes[@]} -gt 0 ]; then
        local fix_str=$(IFS=", "; echo "${fixes[*]}")
        msg_parts+=("🐛 $fix_str")
    fi
    
    if [ ${#refactors[@]} -gt 0 ]; then
        local ref_str=$(IFS=", "; echo "${refactors[*]}")
        msg_parts+=("♻️ $ref_str")
    fi
    
    if [ ${#configs[@]} -gt 0 ]; then
        local cfg_str=$(IFS=", "; echo "${configs[*]}")
        msg_parts+=("⚙️ $cfg_str")
    fi
    
    # Se não detectou nada específico, usar análise genérica
    if [ ${#msg_parts[@]} -eq 0 ]; then
        local file_count=$(echo "$files_changed" | wc -l | xargs)
        msg_parts+=("Atualização: $file_count arquivo(s) modificado(s)")
    fi
    
    msg_parts+=("- Build e deploy")
    
    echo "${msg_parts[*]}"
}

# Função wrapper que tenta usar IA, mas usa análise inteligente como fallback
generate_commit_message() {
    # Tentar gerar com análise inteligente (sempre funciona)
    local message=$(generate_commit_message_with_ai)
    
    # Se a mensagem estiver vazia, usar fallback
    if [ -z "$message" ]; then
        local file_count=$(git diff --cached --name-only 2>/dev/null | wc -l | xargs)
        if [ "$file_count" -eq 0 ]; then
            file_count=$(git diff --name-only 2>/dev/null | wc -l | xargs)
        fi
        message="Atualização: $file_count arquivo(s) - Build e deploy"
    fi
    
    echo "$message"
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

# Commit e push das mudanças para o Git
echo ""
echo -e "${YELLOW}📝 Verificando mudanças no Git...${NC}"

# Verificar se há mudanças para commitar
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}📦 Adicionando mudanças ao Git...${NC}"
    git add .
    
    # Gerar mensagem de commit baseada nas mudanças
    echo -e "${YELLOW}🤖 Gerando mensagem de commit baseada nas mudanças...${NC}"
    COMMIT_MSG=$(generate_commit_message)
    echo -e "${YELLOW}💾 Fazendo commit: ${COMMIT_MSG}${NC}"
    git commit -m "$COMMIT_MSG"
    
    echo -e "${YELLOW}🚀 Fazendo push para o repositório...${NC}"
    git push
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Mudanças enviadas para o Git com sucesso!${NC}"
    else
        echo -e "${RED}❌ Erro ao fazer push para o Git${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Nenhuma mudança para commitar${NC}"
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

