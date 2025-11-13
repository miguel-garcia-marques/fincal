# Variáveis de Ambiente para Passkeys

## 📋 Variáveis Necessárias

Para que as passkeys funcionem corretamente, você precisa configurar duas variáveis de ambiente no backend:

### 1. `RP_ID` (Relying Party ID)
**O que é:** O domínio do seu site (sem protocolo, sem porta, sem caminho)

**Onde encontrar:**
- Olhe no arquivo `lib/config/app_config.dart` - linha 5
- Atualmente está: `https://fincal-f7.web.app/`
- O `RP_ID` seria: `fincal-f7.web.app` (sem `https://` e sem `/`)

**Valores:**
- **Produção:** `fincal-f7.web.app`
- **Desenvolvimento:** `localhost` (já configurado automaticamente)

### 2. `ORIGIN` (URL de Origem)
**O que é:** A URL completa do seu site (com protocolo, sem porta em produção)

**Onde encontrar:**
- Mesmo lugar: `lib/config/app_config.dart` - linha 5
- Atualmente está: `https://fincal-f7.web.app/`
- O `ORIGIN` seria: `https://fincal-f7.web.app` (sem barra final)

**Valores:**
- **Produção:** `https://fincal-f7.web.app`
- **Desenvolvimento:** `http://localhost:8080` (já configurado automaticamente)

---

## 🔧 Como Configurar no Render

### Opção 1: Via Painel do Render (Recomendado)

1. Acesse [https://dashboard.render.com](https://dashboard.render.com)
2. Faça login e selecione seu serviço (`finance-management-backend`)
3. No menu lateral, clique em **Environment**
4. Clique em **Add Environment Variable** para cada variável:

#### Variável 1: RP_ID
- **Key:** `RP_ID`
- **Value:** `fincal-f7.web.app`
- Clique em **Save Changes**

#### Variável 2: ORIGIN
- **Key:** `ORIGIN`
- **Value:** `https://fincal-f7.web.app`
- Clique em **Save Changes**

5. O serviço será reiniciado automaticamente

### Opção 2: Via render.yaml

Adicione as variáveis no arquivo `backend/render.yaml`:

```yaml
envVars:
  - key: RP_ID
    value: fincal-f7.web.app
  - key: ORIGIN
    value: https://fincal-f7.web.app
```

**⚠️ ATENÇÃO:** Se você usar `render.yaml`, certifique-se de que o arquivo não está em um repositório público ou use secrets do Render.

---

## 🔍 Como Descobrir Suas URLs

### Se você mudou a URL do Firebase Hosting:

1. Após fazer deploy:
   ```bash
   firebase deploy --only hosting
   ```

2. O Firebase mostrará a URL onde sua app está hospedada:
   - `https://seu-projeto.web.app`
   - `https://seu-projeto.firebaseapp.com`

3. Use essa URL para configurar:
   - **RP_ID:** `seu-projeto.web.app` (sem `https://`)
   - **ORIGIN:** `https://seu-projeto.web.app` (com `https://`)

### Se você tem um domínio customizado:

- **RP_ID:** `seu-dominio.com` (sem `https://` e sem `www`)
- **ORIGIN:** `https://seu-dominio.com` (com `https://`)

**Nota:** O `RP_ID` deve ser o domínio raiz, não um subdomínio. Por exemplo:
- ✅ Correto: `fincal-f7.web.app`
- ❌ Errado: `app.fincal-f7.web.app`

---

## ✅ Verificação

Após configurar, você pode verificar se está funcionando:

1. Faça login na sua aplicação
2. Tente usar a funcionalidade de passkey
3. Se funcionar, as variáveis estão corretas!

---

## 🐛 Troubleshooting

### Passkeys não funcionam em produção?

1. Verifique se `RP_ID` está correto (sem `https://`, sem porta, sem caminho)
2. Verifique se `ORIGIN` está correto (com `https://`, sem porta em produção)
3. Certifique-se de que a URL corresponde exatamente à URL onde sua app está hospedada
4. Verifique os logs do backend no Render para ver se há erros

### Erro: "Invalid origin" ou "Invalid RP ID"?

- Certifique-se de que `RP_ID` e `ORIGIN` correspondem à URL real da sua app
- Em desenvolvimento, use `localhost` para `RP_ID` e `http://localhost:8080` para `ORIGIN`
- Em produção, use o domínio completo sem porta

---

## 📝 Resumo Rápido

**Para o seu projeto atual:**

```bash
RP_ID=fincal-f7.web.app
ORIGIN=https://fincal-f7.web.app
```

**Para desenvolvimento local (já configurado automaticamente):**

```bash
RP_ID=localhost
ORIGIN=http://localhost:8080
```

