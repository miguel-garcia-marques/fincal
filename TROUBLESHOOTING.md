# Troubleshooting - Tela Branca no Firebase

Se você está vendo uma tela branca ao acessar a aplicação no Firebase, siga estes passos:

## 🔍 Diagnóstico

### 1. Verificar o Console do Navegador

1. Abra a aplicação no navegador
2. Pressione `F12` (ou `Cmd+Option+I` no Mac) para abrir as DevTools
3. Vá para a aba **Console**
4. Procure por erros em vermelho

**Erros comuns:**
- `Failed to load resource: net::ERR_...` - Arquivo não encontrado
- `CORS policy` - Problema de CORS
- `TypeError: Cannot read property...` - Erro JavaScript
- `flutter.js not found` - Arquivo Flutter não carregado

### 2. Verificar a Aba Network

1. Na DevTools, vá para a aba **Network**
2. Recarregue a página (`F5` ou `Cmd+R`)
3. Verifique se todos os arquivos estão sendo carregados (status 200)
4. Procure por arquivos com status 404 (não encontrado)

**Arquivos essenciais que devem carregar:**
- `flutter.js`
- `main.dart.js`
- `flutter_bootstrap.js`
- `flutter_service_worker.js`

### 3. Verificar o Build

Certifique-se de que o build foi feito corretamente:

```bash
# Limpar build anterior
flutter clean

# Fazer build novamente
flutter build web --release

# Verificar se os arquivos foram gerados
ls -la build/web/
```

Você deve ver:
- `index.html`
- `main.dart.js`
- `flutter.js`
- `flutter_bootstrap.js`
- Pasta `assets/`
- Pasta `canvaskit/`

## 🛠️ Soluções Comuns

### Problema 1: Arquivos não encontrados (404)

**Sintoma:** Console mostra erros 404 para arquivos `.js` ou `.wasm`

**Solução:**
1. Verifique se o build foi feito corretamente
2. Certifique-se de que está fazendo deploy da pasta `build/web`
3. Verifique o `firebase.json` - o campo `public` deve ser `build/web`

```bash
# Rebuild completo
flutter clean
flutter pub get
flutter build web --release
firebase deploy --only hosting
```

### Problema 2: Erro de CORS

**Sintoma:** Console mostra erro de CORS ao tentar carregar recursos

**Solução:**
1. Verifique se o backend está configurado para aceitar requisições do Firebase
2. Verifique o arquivo `backend/server.js` - CORS deve estar configurado
3. Adicione o domínio do Firebase nas configurações de CORS

### Problema 3: Erro ao inicializar Supabase

**Sintoma:** Console mostra erro relacionado ao Supabase

**Solução:**
1. Verifique se as credenciais do Supabase estão corretas em `lib/config/supabase_config.dart`
2. Verifique se o Supabase está acessível
3. Teste as credenciais no console do Supabase

### Problema 4: Service Worker bloqueando

**Sintoma:** Aplicação não atualiza após novo deploy

**Solução:**
1. Limpe o cache do navegador
2. Desregistre o service worker:
   - Abra DevTools → Application → Service Workers
   - Clique em "Unregister"
3. Recarregue a página com `Ctrl+Shift+R` (ou `Cmd+Shift+R` no Mac)

### Problema 5: Build em modo debug

**Sintoma:** Aplicação muito lenta ou não carrega

**Solução:**
Sempre use `--release` para produção:

```bash
flutter build web --release
```

Nunca faça deploy de builds em modo debug!

## 🔧 Verificações Adicionais

### Verificar se o Firebase está servindo os arquivos

1. Acesse diretamente: `https://seu-projeto.firebaseapp.com/index.html`
2. Deve mostrar o HTML da aplicação
3. Acesse: `https://seu-projeto.firebaseapp.com/main.dart.js`
4. Deve baixar ou mostrar o arquivo JavaScript

### Verificar logs do Firebase

1. Acesse o [Firebase Console](https://console.firebase.google.com)
2. Vá para **Hosting** → **Logs**
3. Procure por erros de deploy ou acesso

### Testar localmente antes do deploy

```bash
# Build
flutter build web --release

# Servir localmente (simula Firebase)
cd build/web
python3 -m http.server 8080
# ou
npx serve .

# Acesse http://localhost:8080
```

Se funcionar localmente mas não no Firebase, o problema é de configuração do Firebase.

## 📝 Checklist de Deploy

Antes de fazer deploy, verifique:

- [ ] Build feito com `--release`
- [ ] Todos os arquivos em `build/web/` estão presentes
- [ ] `firebase.json` está configurado corretamente
- [ ] URL da API está configurada em `lib/config/api_config.dart`
- [ ] Credenciais do Supabase estão corretas
- [ ] Backend está rodando e acessível
- [ ] CORS está configurado no backend

## 🆘 Ainda não funciona?

Se nenhuma das soluções acima funcionou:

1. **Capture os logs:**
   - Abra o Console do navegador
   - Copie todos os erros
   - Tire screenshots

2. **Verifique o build:**
   ```bash
   flutter doctor -v
   flutter build web --release --verbose
   ```

3. **Teste em modo local:**
   ```bash
   flutter run -d chrome --release
   ```

4. **Verifique a versão do Flutter:**
   ```bash
   flutter --version
   ```
   Certifique-se de estar usando uma versão estável recente.

## 📞 Informações para Debug

Quando pedir ajuda, inclua:

1. Versão do Flutter: `flutter --version`
2. Erros do console (screenshot ou texto)
3. Aba Network (quais arquivos falharam)
4. URL do Firebase onde está deployado
5. Se funciona localmente ou não

