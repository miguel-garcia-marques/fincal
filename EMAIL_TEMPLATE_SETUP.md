# Configuração do Template de Email de Verificação

Este guia explica como configurar o template de email de verificação no Supabase.

## Arquivos Fornecidos

- `email_verification_template.html` - Template HTML completo e responsivo
- `email_verification_template.txt` - Versão em texto simples (fallback)

## Como Configurar no Supabase

### 1. Acessar o Dashboard do Supabase

1. Acesse https://app.supabase.com
2. Faça login na sua conta
3. Selecione o projeto da aplicação FinCal

### 2. Navegar para Email Templates

1. No menu lateral, clique em **Authentication**
2. Clique em **Email Templates** (ou **Templates**)
3. Selecione o template **Confirm signup** (ou **Signup Confirmation**)

### 3. Configurar o Template HTML

1. No campo **Subject**, configure o assunto do email:
   ```
   Verifique seu email - FinCal
   ```

2. No campo **Body** (ou **HTML Body**), cole o conteúdo do arquivo `email_verification_template.html`

3. **Importante**: O Supabase usa variáveis específicas que serão substituídas automaticamente:
   - `{{ .ConfirmationURL }}` - URL completa de confirmação
   - `{{ .Email }}` - Email do usuário
   - `{{ .Token }}` - Token de confirmação
   - `{{ .SiteURL }}` - URL do site configurada no Supabase
   - `{{ .RedirectTo }}` - URL de redirecionamento

### 4. Configurar Versão Texto Simples (Opcional)

1. Se houver um campo **Plain Text Body** ou **Text Version**, cole o conteúdo do arquivo `email_verification_template.txt`

### 5. Salvar e Testar

1. Clique em **Save** para salvar as alterações
2. Para testar, crie uma nova conta de teste na aplicação
3. Verifique se o email foi recebido e se o design está correto

## Variáveis Disponíveis no Supabase

O Supabase suporta as seguintes variáveis nos templates:

| Variável | Descrição |
|----------|-----------|
| `{{ .ConfirmationURL }}` | URL completa para confirmar o email |
| `{{ .Email }}` | Endereço de email do usuário |
| `{{ .Token }}` | Token de confirmação |
| `{{ .TokenHash }}` | Hash do token |
| `{{ .SiteURL }}` | URL base do site (configurada em Settings > API) |
| `{{ .RedirectTo }}` | URL de redirecionamento após confirmação |

## Personalização

### Alterar Cores

As cores usadas no template seguem o tema da aplicação:
- **Preto Principal**: `#1A1A1A`
- **Branco**: `#FFFFFF`
- **Verde (Sucesso)**: `#4CAF50`
- **Cinza Claro**: `#F5F5F5`
- **Cinza Escuro**: `#2A2A2A`

Para alterar, substitua os valores hexadecimais no HTML.

### Alterar Textos

Todos os textos estão em português e podem ser facilmente modificados no HTML.

### Adicionar Logo

Para adicionar um logo da aplicação:

1. Faça upload da imagem para um serviço de hospedagem (ex: Supabase Storage, Cloudinary, etc.)
2. Substitua o ícone de email (✉️) por uma tag `<img>`:

```html
<img src="URL_DO_SEU_LOGO" alt="FinCal" style="width: 80px; height: 80px; border-radius: 50%;" />
```

## Troubleshooting

### Email não está sendo enviado

1. Verifique se o email confirmation está habilitado em **Settings > Auth > Email Auth**
2. Verifique as configurações de SMTP em **Settings > Auth > SMTP Settings**
3. Para desenvolvimento, você pode usar o SMTP padrão do Supabase (limitado)

### Template não está sendo aplicado

1. Certifique-se de que salvou as alterações
2. Limpe o cache do navegador
3. Verifique se está editando o template correto (Confirm signup)

### Link de confirmação não funciona

1. Verifique se a URL de redirecionamento está configurada corretamente em **Settings > Auth > URL Configuration**
2. Verifique se o `emailRedirectTo` no código Flutter corresponde à URL configurada

## Notas Importantes

- O template HTML é responsivo e funciona bem em dispositivos móveis e desktop
- A versão texto simples é usada como fallback por clientes de email que não suportam HTML
- O link de verificação expira em 24 horas (configurável no Supabase)
- Certifique-se de testar o email em diferentes clientes de email (Gmail, Outlook, Apple Mail, etc.)

## Referências

- [Documentação do Supabase - Email Templates](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Configuração de SMTP no Supabase](https://supabase.com/docs/guides/auth/auth-smtp)

