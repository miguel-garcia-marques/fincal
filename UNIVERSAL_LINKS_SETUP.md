# Configuração de PWA para iOS - Links Diretos

Este documento explica como configurar para que os links do QR code abram diretamente no PWA instalado no iPhone.

## ✅ O que já está configurado

1. ✅ `manifest.json` com `scope: "/"` - garante que todos os links sejam tratados pelo PWA
2. ✅ Meta tags iOS melhoradas no `index.html` - melhor suporte a PWA no iOS
3. ✅ Arquivo `apple-app-site-association` básico criado
4. ✅ Headers configurados no `firebase.json` para servir o arquivo corretamente

## 📋 O que você precisa fazer na prática

### 1. Fazer build e deploy

```bash
# Instalar dependências (se ainda não fez)
flutter pub get

# Fazer build
flutter build web --release

# Fazer deploy no Firebase
firebase deploy --only hosting
```

### 2. Instalar o PWA no iPhone

1. Abra o site no Safari do iPhone
2. Toque no botão de compartilhar (quadrado com seta para cima)
3. Role para baixo e selecione **"Adicionar à Tela de Início"**
4. Confirme o nome e adicione

### 3. Como funciona

**Comportamento esperado:**
- Quando você escaneia um QR code e o link é do mesmo domínio do PWA instalado, o iOS deve abrir no contexto do PWA
- Se o PWA estiver instalado, o link abre diretamente nele
- Se não estiver instalado, abre no Safari normalmente

**Limitações do iOS:**
- O iOS não abre automaticamente o PWA quando você escaneia um QR code que abre no Safari primeiro
- O usuário precisa **abrir o link a partir do PWA instalado** ou **compartilhar o link e escolher abrir no PWA**

### 4. Melhorar a experiência do usuário

Para melhorar a experiência, você pode:

**Opção A: Adicionar um botão "Abrir no App" na página de invite**
- Quando alguém acessa o link pelo Safari, mostrar um botão que abre no PWA instalado

**Opção B: Usar um link intermediário**
- Criar uma página que detecta se o PWA está instalado e redireciona

**Opção C: Instruções claras**
- Na página de invite, instruir o usuário a abrir o link a partir do PWA instalado

## 🔍 Verificar se está funcionando

1. **Verificar o arquivo apple-app-site-association:**
   ```
   https://seu-dominio.com/.well-known/apple-app-site-association
   ```
   Deve retornar o JSON sem erros.

2. **Verificar o manifest.json:**
   ```
   https://seu-dominio.com/manifest.json
   ```
   Deve ter `"scope": "/"` configurado.

3. **Testar no iPhone:**
   - Instale o PWA na tela inicial
   - Abra o PWA
   - Dentro do PWA, acesse um link de invite
   - Deve funcionar perfeitamente

## ⚠️ Limitações conhecidas do iOS

O iOS tem limitações com PWAs:

1. **QR Code direto:** Quando você escaneia um QR code, o iOS sempre abre no Safari primeiro, não no PWA instalado
2. **Links externos:** Links compartilhados também abrem no Safari por padrão
3. **Solução:** O usuário precisa abrir o link **a partir do PWA** ou usar o menu de compartilhar e escolher o PWA

## 💡 Solução alternativa recomendada

Para melhorar a experiência, considere adicionar na página de invite (`invite_accept_screen.dart` ou uma página web intermediária):

- Um botão grande "Abrir no App" que tenta abrir o PWA
- Instruções claras para o usuário instalar o PWA se ainda não tiver
- Um link direto que funciona tanto no Safari quanto no PWA

## 📝 Notas finais

- O arquivo `apple-app-site-association` está configurado de forma básica (apenas `webcredentials`)
- Para PWAs, isso é suficiente - não precisa de configuração adicional
- O comportamento depende principalmente do `manifest.json` e das meta tags (já configurados)
- A experiência melhorará quando o usuário usar o PWA instalado regularmente

