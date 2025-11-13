# Configuração de Foto de Perfil

Este documento explica como configurar o bucket de storage no Supabase para permitir upload de fotos de perfil.

## Configuração do Supabase Storage

### 1. Criar o Bucket

1. Acesse o painel do Supabase
2. Vá para **Storage** no menu lateral
3. Clique em **New bucket**
4. Nome do bucket: `profile-pictures`
5. Marque **Public bucket** (para permitir acesso público às imagens)
6. Clique em **Create bucket**

### 2. Configurar Políticas de Segurança (RLS)

Após criar o bucket, configure as políticas RLS (Row Level Security):

#### Política de Upload (INSERT)
- Nome: `Allow authenticated users to upload`
- Operação: `INSERT`
- Política: `authenticated()`
- SQL:
```sql
CREATE POLICY "Allow authenticated users to upload profile pictures"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'profile-pictures' AND (storage.foldername(name))[1] = auth.uid()::text);
```

#### Política de Leitura (SELECT)
- Nome: `Allow public read access`
- Operação: `SELECT`
- Política: `Public`
- SQL:
```sql
CREATE POLICY "Allow public read access to profile pictures"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'profile-pictures');
```

#### Política de Atualização (UPDATE)
- Nome: `Allow users to update their own profile pictures`
- Operação: `UPDATE`
- Política: `authenticated()`
- SQL:
```sql
CREATE POLICY "Allow users to update their own profile pictures"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'profile-pictures' AND (storage.foldername(name))[1] = auth.uid()::text);
```

#### Política de Exclusão (DELETE)
- Nome: `Allow users to delete their own profile pictures`
- Operação: `DELETE`
- Política: `authenticated()`
- SQL:
```sql
CREATE POLICY "Allow users to delete their own profile pictures"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'profile-pictures' AND (storage.foldername(name))[1] = auth.uid()::text);
```

### 3. Estrutura de Arquivos

As fotos de perfil são armazenadas no seguinte formato:
```
profile-pictures/
  └── {userId}/
      └── profile.jpg
```

Cada usuário tem sua própria pasta identificada pelo `userId` do Supabase Auth.

## Funcionalidades Implementadas

- ✅ Upload de foto de perfil (mobile e web)
- ✅ Redimensionamento automático de imagens (máx. 400x400px)
- ✅ Compressão JPEG com qualidade 85%
- ✅ Visualização da foto de perfil
- ✅ Remoção da foto de perfil
- ✅ Atualização do campo `profilePictureUrl` no banco de dados

## Como Usar

1. Na tela de perfil, clique no avatar ou no botão "Adicionar foto"
2. Selecione uma imagem da galeria (mobile) ou do computador (web)
3. A imagem será automaticamente redimensionada e enviada para o Supabase Storage
4. A URL da imagem será salva no campo `profilePictureUrl` do usuário
5. Para remover a foto, clique no botão "X" no canto superior direito do avatar

## Notas Importantes

- As imagens são redimensionadas automaticamente para otimizar o armazenamento
- O formato de saída é sempre JPEG
- Cada usuário só pode fazer upload/atualizar/deletar suas próprias fotos
- As fotos são públicas para leitura (qualquer pessoa pode ver)
- O bucket deve ser criado manualmente no Supabase antes de usar a funcionalidade

