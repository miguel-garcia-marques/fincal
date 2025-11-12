import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/wallet_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../models/invite.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import 'login_screen.dart';
import 'home_screen.dart';

// Importação para web (apenas compilado quando kIsWeb é true)
import 'dart:html' as html show window;

class InviteAcceptScreen extends StatefulWidget {
  final String token;

  const InviteAcceptScreen({
    super.key,
    required this.token,
  });

  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen> {
  final _walletService = WalletService();
  final _authService = AuthService();
  final _userService = UserService();
  
  Invite? _invite;
  bool _isLoading = true;
  bool _isAccepting = false;
  String? _error;
  String? _successMessage;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadInvite();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    if (_authService.isAuthenticated) {
      try {
        final user = await _userService.getCurrentUser();
        if (mounted) {
          setState(() {
            _currentUserName = user?.name;
          });
        }
      } catch (e) {
        // Ignorar erro, apenas não mostrar nome
      }
    }
  }

  Future<void> _loadInvite() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final invite = await _walletService.getInviteByToken(widget.token);
      
      if (mounted) {
        setState(() {
          _invite = invite;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar convite: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptInvite() async {
    // Mostrar diálogo para escolher usuário
    final choice = await _showUserChoiceDialog();
    
    if (choice == null) {
      // Usuário cancelou
      return;
    }

    if (choice == 'login') {
      // Fazer logout da conta atual antes de fazer login com outra conta
      // Isso evita conflitos de sessão no Supabase
      try {
        await _authService.signOut();
      } catch (e) {
        // Ignorar erros no logout - continuar mesmo assim
      }
      
      // Aguardar um pouco para garantir que o logout foi processado
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Redirecionar para login com o token do invite
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => LoginScreen(inviteToken: widget.token),
          ),
        );
      }
      return;
    }

    // choice == 'current' - aceitar com usuário atual
    if (!_authService.isAuthenticated) {
      // Se não estiver autenticado, redirecionar para login
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => LoginScreen(inviteToken: widget.token),
          ),
        );
      }
      return;
    }

    await _performAcceptInvite();
  }

  Future<String?> _showUserChoiceDialog() async {
    final isAuthenticated = _authService.isAuthenticated;
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Aceitar Convite',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Como deseja aceitar este convite?',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.darkGray,
                ),
              ),
              const SizedBox(height: 20),
              if (isAuthenticated) ...[
                // Opção 1: Aceitar com usuário atual
                InkWell(
                  onTap: () => Navigator.of(context).pop('current'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.black.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          color: AppTheme.black,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Usar conta atual',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_currentUserName != null)
                                Text(
                                  _currentUserName!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.darkGray,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: AppTheme.darkGray,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Opção 2: Fazer login com outro usuário
                InkWell(
                  onTap: () => Navigator.of(context).pop('login'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.black.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.swap_horiz,
                          color: AppTheme.black,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Fazer login com outra conta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: AppTheme.darkGray,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Se não estiver autenticado, apenas opção de login
                InkWell(
                  onTap: () => Navigator.of(context).pop('login'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.black.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.login,
                          color: AppTheme.black,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Fazer login para aceitar',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: AppTheme.darkGray,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Fechar apenas o diálogo
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: AppTheme.darkGray,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performAcceptInvite() async {
    setState(() {
      _isAccepting = true;
      _error = null;
    });

    try {
      final result = await _walletService.acceptInvite(widget.token);
      
      if (mounted) {
        setState(() {
          _successMessage = result['message'] as String? ?? 'Convite aceito com sucesso!';
          _isAccepting = false;
        });

        // Limpar a URL imediatamente após aceitar o convite
        if (kIsWeb) {
          html.window.history.replaceState(null, '', '/');
        }

        // Aguardar um pouco para mostrar a mensagem e depois navegar para AuthWrapper
        // O AuthWrapper vai detectar a autenticação e redirecionar para a tela apropriada
        await Future.delayed(const Duration(milliseconds: 1500));
        
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const AuthWrapper(),
            ),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro ao aceitar convite: ${e.toString()}';
          _isAccepting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _buildContent(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'Carregando informações do convite...',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.darkGray,
            ),
          ),
        ],
      );
    }

    if (_error != null && _invite == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: AppTheme.expenseRed,
          ),
          const SizedBox(height: 16),
          Text(
            'Erro',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.darkGray,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (kIsWeb) {
                // Limpar a URL removendo os parâmetros de query
                html.window.history.replaceState(null, '', '/');
              }
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.black,
              foregroundColor: AppTheme.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
            ),
            child: const Text('Fechar'),
          ),
        ],
      );
    }

    if (_invite == null) {
      return const SizedBox.shrink();
    }

    // Verificar se expirou
    if (_invite!.isExpired) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 64,
            color: AppTheme.expenseRed,
          ),
          const SizedBox(height: 16),
          Text(
            'Convite Expirado',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Este convite expirou em ${_formatDate(_invite!.expiresAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.darkGray,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (kIsWeb) {
                // Limpar a URL removendo os parâmetros de query
                html.window.history.replaceState(null, '', '/');
              }
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.black,
              foregroundColor: AppTheme.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
            ),
            child: const Text('Fechar'),
          ),
        ],
      );
    }

    // Verificar se já foi aceito
    if (_invite!.status == 'accepted') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 64,
            color: AppTheme.incomeGreen,
          ),
          const SizedBox(height: 16),
          Text(
            'Convite Já Aceito',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Este convite já foi aceito anteriormente.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.darkGray,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (kIsWeb) {
                // Limpar a URL removendo os parâmetros de query
                html.window.history.replaceState(null, '', '/');
              }
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.black,
              foregroundColor: AppTheme.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
            ),
            child: const Text('Ir para App'),
          ),
        ],
      );
    }

    // Mostrar informações do convite
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ícone
        Icon(
          Icons.calendar_today,
          size: 64,
          color: AppTheme.black,
        ),
        const SizedBox(height: 24),
        
        // Título
        Text(
          'Convite para Carteira Calendário',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.black,
          ),
        ),
        const SizedBox(height: 8),
        
        // Subtítulo
        Text(
          'Você foi convidado para participar de uma carteira',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            color: AppTheme.darkGray,
          ),
        ),
        const SizedBox(height: 32),
        
        // Informações da carteira
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.offWhite,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _invite!.wallet?.name ?? 'Carteira Calendário',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Convidado por: ${_invite!.invitedByName ?? (_invite!.invitedBy.isNotEmpty ? _invite!.invitedBy : 'Usuário')}',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.darkGray,
                ),
              ),
              const SizedBox(height: 12),
              // Badge de permissão
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _invite!.permission == 'read'
                      ? AppTheme.incomeGreen.withOpacity(0.1)
                      : AppTheme.expenseRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _invite!.permission == 'read'
                          ? Icons.visibility
                          : Icons.edit,
                      size: 16,
                      color: _invite!.permission == 'read'
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _invite!.permission == 'read'
                          ? 'Apenas Visualizar'
                          : 'Criar Transações',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _invite!.permission == 'read'
                            ? AppTheme.incomeGreen
                            : AppTheme.expenseRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Mensagem de sucesso
        if (_successMessage != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.incomeGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppTheme.incomeGreen,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _successMessage!,
                    style: TextStyle(
                      color: AppTheme.incomeGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        
        // Erro
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.expenseRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: AppTheme.expenseRed,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: AppTheme.expenseRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        
        if (_error != null) const SizedBox(height: 16),
        
        // Botão de aceitar
        if (_successMessage == null)
          ElevatedButton(
            onPressed: _isAccepting ? null : _acceptInvite,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.black,
              foregroundColor: AppTheme.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isAccepting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.white),
                    ),
                  )
                : const Text(
                    'Aceitar Convite',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        
        const SizedBox(height: 12),
        
        // Botão de cancelar
        if (_successMessage == null)
          TextButton(
            onPressed: () {
              // Limpar a URL e navegar para home
              if (kIsWeb) {
                // Limpar a URL removendo os parâmetros de query
                html.window.history.replaceState(null, '', '/');
              }
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            },
            child: const Text(
              'Cancelar',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.darkGray,
              ),
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
