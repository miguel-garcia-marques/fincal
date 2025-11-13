import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  final StorageService _storageService = StorageService();
  final TextEditingController _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUploadingPicture = false;
  bool _isDeletingAccount = false;
  String? _email;
  String? _profilePictureUrl;
  Uint8List? _selectedImageBytes;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _userService.getCurrentUser(forceRefresh: true);
      final email = _authService.currentUser?.email;
      
      // Obter nome do Supabase se disponível (prioridade sobre MongoDB)
      String? displayName;
      try {
        final supabaseUser = _authService.currentUser;
        if (supabaseUser != null) {
          displayName = supabaseUser.userMetadata?['display_name'] as String?;
        }
      } catch (e) {
        // Ignorar erro ao obter display_name do Supabase
      }
      
      if (mounted) {
        setState(() {
          // Usar nome do Supabase se disponível, senão usar do MongoDB, senão string vazia
          _nameController.text = displayName ?? user?.name ?? '';
          _email = email ?? user?.email;
          _profilePictureUrl = user?.profilePictureUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao carregar dados do usuário: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectAndUploadPicture() async {
    try {
      setState(() {
        _isUploadingPicture = true;
        _errorMessage = null;
      });

      // Selecionar imagem
      final imageBytes = await _storageService.pickImage();
      
      if (imageBytes == null) {
        // Usuário cancelou a seleção
        setState(() {
          _isUploadingPicture = false;
        });
        return;
      }

      // Fazer upload da imagem (deleta a foto antiga se existir)
      final imageUrl = await _storageService.uploadProfilePicture(
        imageBytes,
        currentProfilePictureUrl: _profilePictureUrl,
      );
      
      // Atualizar perfil do usuário com a URL da imagem
      await _userService.updateProfilePicture(imageUrl);
      
      if (mounted) {
        setState(() {
          _profilePictureUrl = imageUrl;
          _selectedImageBytes = imageBytes;
          _isUploadingPicture = false;
          _successMessage = 'Foto de perfil atualizada com sucesso!';
        });
        
        // Limpar mensagem de sucesso após 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingPicture = false;
          _errorMessage = 'Erro ao fazer upload da foto: $e';
        });
      }
    }
  }

  Future<void> _removePicture() async {
    try {
      setState(() {
        _isUploadingPicture = true;
        _errorMessage = null;
      });

      // Deletar imagem do storage
      await _storageService.deleteProfilePicture();
      
      // Atualizar perfil do usuário removendo a URL
      await _userService.updateProfilePicture('');
      
      if (mounted) {
        setState(() {
          _profilePictureUrl = null;
          _selectedImageBytes = null;
          _isUploadingPicture = false;
          _successMessage = 'Foto de perfil removida com sucesso!';
        });
        
        // Limpar mensagem de sucesso após 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingPicture = false;
          _errorMessage = 'Erro ao remover foto: $e';
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _userService.updateUserName(_nameController.text.trim());
      
      if (mounted) {
        setState(() {
          _isSaving = false;
          _successMessage = 'Perfil atualizado com sucesso!';
        });
        
        // Limpar mensagem de sucesso após 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Erro ao salvar: $e';
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    // Mostrar diálogo de confirmação
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Conta'),
        content: const Text(
          'Tem certeza que deseja deletar sua conta?\n\n'
          'Esta ação é IRREVERSÍVEL e irá deletar:\n'
          '• Seu perfil e dados pessoais\n'
          '• Todas as suas carteiras\n'
          '• Todas as suas transações\n'
          '• Todo o histórico de períodos\n'
          '• Sua foto de perfil\n\n'
          'Esta ação não pode ser desfeita!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.expenseRed,
            ),
            child: const Text('Deletar Conta'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    // Segunda confirmação
    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmação Final'),
        content: const Text(
          'Esta é sua última chance de cancelar.\n\n'
          'Tem CERTEZA ABSOLUTA que deseja deletar sua conta permanentemente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.expenseRed,
            ),
            child: const Text('SIM, DELETAR'),
          ),
        ],
      ),
    );

    if (finalConfirm != true) {
      return;
    }

    setState(() {
      _isDeletingAccount = true;
      _errorMessage = null;
    });

    try {
      // 1. Deletar foto de perfil do Supabase Storage
      if (_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty) {
        try {
          await _storageService.deleteProfilePicture();
        } catch (e) {
          // Continuar mesmo se falhar ao deletar foto
          print('Erro ao deletar foto de perfil: $e');
        }
      }

      // 2. Deletar conta no backend (deleta MongoDB e todos os dados)
      await _userService.deleteAccount();

      // 3. Fazer logout do Supabase (limpa sessão)
      // Nota: Para deletar completamente do Supabase Auth, o usuário precisa fazer isso manualmente
      // através do dashboard do Supabase ou usar Admin API
      await _authService.signOut();
      
      // 4. Limpar todos os dados locais
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      } catch (e) {
        // Ignorar erro ao limpar dados locais
      }

      // 5. Navegar para AuthWrapper (que vai redirecionar para login)
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const AuthWrapper(),
          ),
          (route) => false,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conta deletada com sucesso'),
            backgroundColor: AppTheme.incomeGreen,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeletingAccount = false;
          _errorMessage = 'Erro ao deletar conta: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: AppTheme.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Avatar/Icon com opção de upload
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: _isUploadingPicture ? null : _selectAndUploadPicture,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primaryColor.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: _isUploadingPicture
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _selectedImageBytes != null
                                      ? ClipOval(
                                          child: Image.memory(
                                            _selectedImageBytes!,
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : _profilePictureUrl != null
                                          ? ClipOval(
                                              child: Image.network(
                                                _profilePictureUrl!,
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Icon(
                                                    Icons.person,
                                                    size: 60,
                                                    color: AppTheme.primaryColor,
                                                  );
                                                },
                                                loadingBuilder: (context, child, loadingProgress) {
                                                  if (loadingProgress == null) {
                                                    return child;
                                                  }
                                                  return const Center(
                                                    child: CircularProgressIndicator(),
                                                  );
                                                },
                                              ),
                                            )
                                          : Icon(
                                              Icons.person,
                                              size: 60,
                                              color: AppTheme.primaryColor,
                                            ),
                            ),
                          ),
                          // Botão de remover foto (se houver foto)
                          if ((_profilePictureUrl != null || _selectedImageBytes != null) && !_isUploadingPicture)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: _removePicture,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.expenseRed,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppTheme.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: AppTheme.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: _isUploadingPicture ? null : _selectAndUploadPicture,
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: Text(
                          _profilePictureUrl != null || _selectedImageBytes != null
                              ? 'Alterar foto'
                              : 'Adicionar foto',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Mensagens de erro/sucesso
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.expenseRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.expenseRed.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: AppTheme.expenseRed,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: AppTheme.expenseRed,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    if (_successMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.incomeGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.incomeGreen.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: AppTheme.incomeGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: TextStyle(
                                  color: AppTheme.incomeGreen,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Nome
                    Text(
                      'Nome',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Seu nome',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.lighterGray),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.lighterGray),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Por favor, insira um nome';
                        }
                        if (value.trim().length < 2) {
                          return 'O nome deve ter pelo menos 2 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    // Email (somente leitura)
                    Text(
                      'Email',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.offWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.lighterGray),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _email ?? 'Não disponível',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ),
                          Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O email não pode ser alterado',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Botão salvar
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: AppTheme.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Salvar Alterações',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Divisor
                    const Divider(),
                    const SizedBox(height: 24),
                    
                    // Seção de deletar conta
                    Text(
                      'Zona Perigosa',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppTheme.expenseRed,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ao deletar sua conta, todos os seus dados serão permanentemente removidos e não poderão ser recuperados.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _isDeletingAccount ? null : _deleteAccount,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: AppTheme.expenseRed,
                        side: BorderSide(color: AppTheme.expenseRed),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isDeletingAccount
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.expenseRed,
                                ),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_forever, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Deletar Conta',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

