@echo off
REM Script para fazer build de produção com credenciais do Supabase
REM 
REM USO:
REM 1. Edite este arquivo e substitua as credenciais abaixo
REM 2. Execute: build_prod.bat

REM ⚠️ SUBSTITUA PELAS SUAS CREDENCIAIS DO SUPABASE
set SUPABASE_URL=https://seu-projeto.supabase.co
set SUPABASE_ANON_KEY=sua-chave-anon-aqui

REM Build para produção
flutter build web --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%

echo ✅ Build concluído! Arquivos em: build/web/

