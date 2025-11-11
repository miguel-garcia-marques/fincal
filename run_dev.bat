@echo off
REM Script para executar o app em desenvolvimento com credenciais do Supabase
REM 
REM USO:
REM 1. Edite este arquivo e substitua as credenciais abaixo
REM 2. Execute: run_dev.bat

REM ⚠️ SUBSTITUA PELAS SUAS CREDENCIAIS DO SUPABASE
set SUPABASE_URL=https://seu-projeto.supabase.co
set SUPABASE_ANON_KEY=sua-chave-anon-aqui

REM Executar Flutter com as credenciais
flutter run -d chrome --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%

