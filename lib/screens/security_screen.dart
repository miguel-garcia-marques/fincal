import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/app_theme.dart';
import '../services/passkey_service.dart';
import '../services/auth_service.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final PasskeyService _passkeyService = PasskeyService();
  final AuthService _authService = AuthService();
  
  bool _isLoading = false;
  bool _isRegisteringPasskey = false;
  List<Map<String, dynamic>> _passkeys = [];
  String? _errorMessage;
  String? _successMessage;
  bool? _passkeySupported; // Cache do resultado de isSupported

  @override
  void initState() {
    super.initState();
    // Verificar suporte apenas uma vez e cachear
    if (kIsWeb) {
      try {
        _passkeySupported = _passkeyService.isSupported;
        if (_passkeySupported == true) {
          _loadPasskeys();
        }
      } catch (e) {
        print('[SecurityScreen] Erro ao verificar suporte a passkey: $e');
        _passkeySupported = false;
      }
    } else {
      _passkeySupported = false;
    }
  }

  Future<void> _loadPasskeys() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final passkeys = await _passkeyService.listPasskeys();
      if (mounted) {
        setState(() {
          _passkeys = passkeys;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erro ao carregar passkeys: $e';
        });
      }
    }
  }

  Future<void> _registerPasskey() async {
    if (!_authService.isAuthenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você precisa estar autenticado para registrar uma passkey'),
            backgroundColor: AppTheme.expenseRed,
          ),
        );
      }
      return;
    }

    // Mostrar diálogo para inserir nome
    final nameController = TextEditingController();
    final nameResult = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nomear Passkey'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nome (opcional)',
            hintText: 'Ex: MacBook Pro, iPhone, etc.',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim().isEmpty ? '' : value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(nameController.text.trim().isEmpty ? '' : nameController.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    // Se cancelou (retornou null), não fazer nada
    if (nameResult == null) {
      return;
    }

    setState(() {
      _isRegisteringPasskey = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final name = nameResult.trim().isEmpty ? null : nameResult.trim();
      await _passkeyService.registerPasskey(name: name);
      
      if (mounted) {
        setState(() {
          _isRegisteringPasskey = false;
          _successMessage = 'Passkey registrada com sucesso!';
        });
        
        // Recarregar lista de passkeys
        await _loadPasskeys();
        
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
          _isRegisteringPasskey = false;
          _errorMessage = 'Erro ao registrar passkey: $e';
        });
      }
    }
  }

  Future<void> _editPasskeyName(String passkeyId, String? currentName) async {
    final nameController = TextEditingController(text: currentName ?? '');
    final nameResult = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Nome da Passkey'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nome',
            hintText: 'Ex: MacBook Pro, iPhone, etc.',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim().isEmpty ? null : value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(nameController.text.trim().isEmpty ? null : nameController.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    // Se cancelou (retornou null), não fazer nada
    if (nameResult == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final name = nameResult.trim().isEmpty ? null : nameResult.trim();
      await _passkeyService.updatePasskeyName(passkeyId, name);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _successMessage = 'Nome da passkey atualizado com sucesso!';
        });
        
        // Recarregar lista de passkeys
        await _loadPasskeys();
        
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
          _isLoading = false;
          _errorMessage = 'Erro ao atualizar nome da passkey: $e';
        });
      }
    }
  }

  Future<void> _deletePasskey(String credentialId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Passkey'),
        content: const Text(
          'Tem certeza que deseja deletar esta passkey?\n\n'
          'Você não poderá mais usar este dispositivo para fazer login sem senha.',
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
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _passkeyService.deletePasskey(credentialId);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _successMessage = 'Passkey deletada com sucesso!';
        });
        
        // Recarregar lista de passkeys
        await _loadPasskeys();
        
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
          _isLoading = false;
          _errorMessage = 'Erro ao deletar passkey: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Segurança'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: AppTheme.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mensagens de erro/sucesso
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.expenseRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.expenseRed),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppTheme.expenseRed),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppTheme.expenseRed),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            if (_successMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.incomeGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.incomeGreen),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: AppTheme.incomeGreen),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: TextStyle(color: AppTheme.incomeGreen),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Seção de Passkeys
            if (kIsWeb && _passkeySupported == true) ...[
              Text(
                'Passkeys',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.black,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Passkeys permitem fazer login sem senha usando biometria ou PIN do seu dispositivo.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 24),
              
              // Botão para registrar nova passkey
              OutlinedButton.icon(
                onPressed: _isRegisteringPasskey ? null : _registerPasskey,
                icon: _isRegisteringPasskey
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint, size: 20),
                label: Text(_isRegisteringPasskey 
                    ? 'Registrando...' 
                    : 'Registrar Nova Passkey'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: const BorderSide(color: AppTheme.black),
                ),
              ),
              const SizedBox(height: 32),
              
              // Lista de passkeys registradas
              if (_isLoading) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ] else if (_passkeys.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.offWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.lighterGray),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Nenhuma passkey registrada ainda.',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Text(
                  'Passkeys Registradas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.black,
                      ),
                ),
                const SizedBox(height: 12),
                ..._passkeys.map((passkey) {
                  final passkeyId = passkey['_id'] as String? ?? passkey['credentialID'] as String;
                  final name = passkey['name'] as String?;
                  final deviceType = passkey['deviceType'] as String? ?? 'Desconhecido';
                  final displayName = name ?? deviceType;
                  final lastUsed = passkey['lastUsedAt'] as String?;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.fingerprint, color: AppTheme.black),
                      title: Text(displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (name != null && deviceType != 'Desconhecido')
                            Text(
                              deviceType,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          if (lastUsed != null)
                            Text('Último uso: ${_formatDate(lastUsed)}')
                          else
                            const Text('Nunca usado'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: AppTheme.black),
                            onPressed: () => _editPasskeyName(passkeyId, name),
                            tooltip: 'Editar nome',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.expenseRed),
                            onPressed: () => _deletePasskey(passkeyId),
                            tooltip: 'Deletar',
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ] else ...[
              // Mensagem quando passkeys não são suportadas
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.offWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.lighterGray),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        kIsWeb
                            ? 'Passkeys não são suportadas neste navegador.'
                            : 'Passkeys estão disponíveis apenas na versão web.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return 'Agora mesmo';
          }
          return '${difference.inMinutes} minutos atrás';
        }
        return '${difference.inHours} horas atrás';
      } else if (difference.inDays == 1) {
        return 'Ontem';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} dias atrás';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateStr;
    }
  }
}

