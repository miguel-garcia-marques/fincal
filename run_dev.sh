#!/bin/bash

# Script para executar o app em desenvolvimento com credenciais do Supabase
# 
# USO:
# 1. Edite este arquivo e substitua as credenciais abaixo
# 2. Execute: chmod +x run_dev.sh
# 3. Execute: ./run_dev.sh

# ⚠️ SUBSTITUA PELAS SUAS CREDENCIAIS DO SUPABASE
SUPABASE_URL="https://fjuedycchyiynyqivkch.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZqdWVkeWNjaHlpeW55cWl2a2NoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI2MTgwOTIsImV4cCI6MjA3ODE5NDA5Mn0.vIeykvK-puQx8q52AARQY8fLl_7EvzL8Vz7VFANKBNo"

# Executar Flutter com as credenciais
flutter run -d chrome \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

