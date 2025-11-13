# Configuração de Ícones - FinCal

## ✅ Ícones Configurados

Todos os ícones foram criados e configurados para:
- **macOS**: Ícones em todos os tamanhos necessários
- **Web (Browser)**: Favicons em múltiplos tamanhos
- **iOS/iPhone**: Apple touch icons em todos os tamanhos
- **PWA**: Ícones para Progressive Web App

## 📋 Arquivos Criados

### Ícones Web (web/icons/):
- Icon-57.png, Icon-60.png, Icon-72.png, Icon-76.png
- Icon-114.png, Icon-120.png, Icon-144.png, Icon-152.png
- Icon-180.png, Icon-192.png, Icon-512.png

### Favicons (web/):
- favicon-16.png, favicon-32.png, favicon-96.png, favicon.png

## 🔄 Como Atualizar os Ícones

### 1. Rebuild Completo
```bash
# Limpar build anterior
flutter clean

# Obter dependências
flutter pub get

# Build para web
flutter build web --release
```

### 2. Limpar Cache do Browser

#### Chrome/Edge:
1. Abra DevTools (F12)
2. Clique com botão direito no botão de recarregar
3. Selecione "Limpar cache e recarregar forçadamente" (ou "Empty Cache and Hard Reload")

#### Safari (macOS):
1. Desenvolver > Limpar Caches
2. Ou Cmd+Option+E

#### iPhone Safari:
1. Configurações > Safari > Limpar Histórico e Dados do Site
2. Ou remova e reinstale o PWA

### 3. Limpar Cache do PWA

Se a aplicação já foi instalada como PWA:

#### Chrome:
1. Abra `chrome://serviceworker-internals/`
2. Encontre o service worker da aplicação
3. Clique em "Unregister"
4. Feche todas as abas da aplicação
5. Reabra a aplicação

#### iPhone:
1. Remova o ícone do ecrã principal
2. Limpe o cache do Safari
3. Acesse a aplicação novamente
4. Adicione ao ecrã principal novamente

### 4. Verificar se os Ícones Estão Corretos

1. Abra a aplicação no browser
2. Abra DevTools (F12)
3. Vá para a aba **Application** (ou **Aplicativo**)
4. No menu lateral, clique em **Manifest**
5. Verifique se os ícones aparecem corretamente
6. Clique em cada ícone para ver se carrega

### 5. Testar no iPhone

1. Acesse a aplicação no Safari do iPhone
2. Toque no botão de compartilhar
3. Selecione "Adicionar ao Ecrã Principal"
4. O ícone deve aparecer com o logo FinCal

## 🐛 Troubleshooting

### Ícone não aparece no browser:
- Verifique se fez `flutter build web` após as mudanças
- Limpe o cache do browser (ver acima)
- Verifique o console do browser para erros 404 nos ícones

### Ícone não aparece no iPhone:
- Certifique-se de que está usando Safari (não Chrome)
- Remova o PWA anterior e adicione novamente
- Verifique se o arquivo `Icon-180.png` existe em `build/web/icons/`

### Ícone não aparece no macOS:
- Recompile a aplicação: `flutter run -d macos`
- Ou faça rebuild: `flutter clean && flutter build macos`

## 📝 Notas

- Os ícones são copiados automaticamente do diretório `web/` para `build/web/` durante o build
- O Flutter não modifica os arquivos em `web/`, apenas os copia
- Sempre faça `flutter build web` após alterar arquivos em `web/`

