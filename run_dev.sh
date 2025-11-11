#!/bin/bash

# Script para executar o app em desenvolvimento com credenciais do Supabase
# 
# USO:
# 1. Edite este arquivo e substitua as credenciais abaixo
# 2. Execute: chmod +x run_dev.sh
# 3. Execute: ./run_dev.sh

# ⚠️ SUBSTITUA PELAS SUAS CREDENCIAIS DO SUPABASE
SUPABASE_URL="https://seu-projeto.supabase.co"
SUPABASE_ANON_KEY="sua-chave-anon-aqui"

# Executar Flutter com as credenciais
flutter run -d chrome \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

