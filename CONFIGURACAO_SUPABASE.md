# Como Configurar Credenciais do Supabase

Existem 3 formas de configurar as credenciais do Supabase:

## Opção 1: Arquivo de Configuração (Recomendado para Desenvolvimento)

1. Copie o arquivo de exemplo:
   ```bash
   cp lib/config/supabase_config.dart.example lib/config/supabase_config.dart
   ```

2. Edite `lib/config/supabase_config.dart` e adicione suas credenciais:
   ```dart
   static const String url = 'https://seu-projeto.supabase.co';
   static const String anonKey = 'sua-chave-anon-aqui';
   ```

3. Execute normalmente:
   ```bash
   flutter run -d chrome
   ```

**Vantagens:**
- ✅ Fácil de usar
- ✅ Não precisa passar argumentos toda vez
- ✅ Bom para desenvolvimento

**Desvantagens:**
- ⚠️ Credenciais ficam no código (mas estão no .gitignore)

---

## Opção 2: Usando --dart-define (Recomendado para Produção)

Execute o Flutter passando as variáveis:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://seu-projeto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sua-chave-anon-aqui
```

Para build de produção:
```bash
flutter build web \
  --dart-define=SUPABASE_URL=https://seu-projeto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sua-chave-anon-aqui
```

**Vantagens:**
- ✅ Credenciais não ficam no código
- ✅ Ideal para CI/CD e produção
- ✅ Diferentes credenciais para dev/staging/prod

**Desvantagens:**
- ⚠️ Precisa passar argumentos toda vez

---

## Opção 3: Script de Execução (Melhor dos dois mundos)

Crie um script para facilitar:

### macOS/Linux (`run.sh`):
```bash
#!/bin/bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://seu-projeto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sua-chave-anon-aqui
```

Torne executável:
```bash
chmod +x run.sh
```

Execute:
```bash
./run.sh
```

### Windows (`run.bat`):
```batch
@echo off
flutter run -d chrome ^
  --dart-define=SUPABASE_URL=https://seu-projeto.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=sua-chave-anon-aqui
```

Execute:
```cmd
run.bat
```

---

## Como Funciona

O código em `lib/config/supabase_config.dart` verifica primeiro se há variáveis `--dart-define`:

1. Se `--dart-define` foi usado → usa essas variáveis
2. Se não → usa os valores hardcoded no arquivo

Isso permite flexibilidade: você pode usar o arquivo para desenvolvimento e `--dart-define` para produção.

---

## Exemplo Completo

### Desenvolvimento Local:
```bash
# Edite lib/config/supabase_config.dart com suas credenciais
flutter run -d chrome
```

### Produção/CI:
```bash
flutter build web \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

---

## Onde Obter as Credenciais

1. Acesse https://supabase.com
2. Vá no seu projeto
3. Settings → API
4. Copie:
   - **URL**: `https://xxxxx.supabase.co`
   - **anon/public key**: `eyJhbGc...`

---

## Segurança

⚠️ **IMPORTANTE:**
- O arquivo `lib/config/supabase_config.dart` está no `.gitignore`
- NUNCA commite credenciais reais
- Use `--dart-define` em ambientes de produção
- A chave "anon" é pública, mas ainda assim não deve ser commitada

