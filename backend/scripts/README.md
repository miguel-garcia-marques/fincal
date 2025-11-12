# Scripts de Migração

## migrate_transactions.js

Este script migra transações antigas que não têm `walletId` ou têm um `walletId` inválido para a wallet pessoal do usuário.

### Como executar:

```bash
cd backend
node scripts/migrate_transactions.js
```

### O que o script faz:

1. **Identifica transações problemáticas**: Encontra todas as transações que:
   - Não têm `walletId`
   - Têm `walletId` inválido (não é um ObjectId válido)
   - Têm `walletId` que não existe no banco de dados

2. **Encontra ou cria wallets pessoais**: Para cada usuário afetado:
   - Busca a wallet pessoal (onde `ownerId` = `userId`)
   - Se não existir, cria uma nova wallet pessoal

3. **Migra as transações**: Atualiza todas as transações problemáticas com o `walletId` correto da wallet pessoal do usuário

4. **Verifica o resultado**: Confirma que todas as transações foram migradas corretamente

### Quando executar:

- Quando transações antigas não aparecem na aplicação
- Após migrar de um sistema que usava apenas `userId` para um sistema com `walletId`
- Se você receber avisos no console do servidor sobre transações antigas

### Nota:

O servidor agora tem um fallback automático que busca transações antigas por `userId` quando não encontra transações por `walletId`. Isso permite que as transações apareçam na app mesmo antes de executar a migração, mas é recomendado executar o script para corrigir os dados permanentemente.

---

## consolidate_duplicate_wallets.js

Este script consolida wallets duplicadas de usuários, movendo todas as transações para uma única wallet pessoal.

### Como executar:

```bash
cd backend
node scripts/consolidate_duplicate_wallets.js
```

### O que o script faz:

1. **Identifica usuários com múltiplas wallets**: Encontra todos os usuários que têm mais de uma wallet pessoal (onde `ownerId` = `userId`)

2. **Escolhe wallet principal**: Para cada usuário:
   - Se o usuário tem `personalWalletId` e essa wallet existe, usa ela como principal
   - Caso contrário, usa a wallet mais antiga (primeira criada)

3. **Move transações**: Para cada wallet duplicada:
   - Move todas as transações da collection `transactions_${duplicateWalletId}` para `transactions_${mainWalletId}`
   - Atualiza o `walletId` de todas as transações movidas

4. **Limpa dados**: Para cada wallet duplicada:
   - Deleta todos os membros (WalletMember)
   - Deleta todos os convites (Invite)
   - Deleta a wallet duplicada

5. **Atualiza usuário**: Atualiza o `personalWalletId` do usuário para apontar para a wallet principal

### Quando executar:

- Quando um usuário tem múltiplas wallets pessoais aparecendo na interface
- Quando há erros relacionados a múltiplas collections de transações para o mesmo usuário
- Após corrigir bugs que permitiam criar múltiplas wallets pessoais

### Importante:

⚠️ **Este script modifica dados permanentemente**. Certifique-se de fazer backup do banco de dados antes de executar.

O script é seguro e:
- Não perde transações (todas são movidas para a wallet principal)
- Mantém a wallet mais antiga ou a que está no `personalWalletId`
- Atualiza corretamente todas as referências

### Nota:

Após executar este script, o sistema impedirá a criação de novas wallets duplicadas através de validação no modelo Wallet.

