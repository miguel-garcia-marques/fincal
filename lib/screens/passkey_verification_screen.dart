import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/passkey_service.dart';
import '../theme/app_theme.dart';
import '../main.dart';

class PasskeyVerificationScreen extends StatefulWidget {
  final String email;
  
  const PasskeyVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<PasskeyVerificationScreen> createState() => _PasskeyVerificationScreenState();
}

class _PasskeyVerificationScreenState extends State<PasskeyVerificationScreen> {
  final _authService = AuthService();
  final _passkeyService = PasskeyService();
  bool _isAuthenticating = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isDisposed = false;
  bool _rateLimitExceeded = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _authenticateWithPasskey() async {
    if (_isAuthenticating || _isDisposed || !mounted || _rateLimitExceeded) return;
    
    setState(() {
      _isAuthenticating = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // Autenticar com passkey
      final result = await _passkeyService.authenticateWithPasskey(widget.email);
      
      if (!mounted || _isDisposed) return;
      
      if (result['success'] == true) {
        final userEmail = result['email'] as String?;
        final token = result['token'] as String?;
        
        // Se tivermos token, criar sessão automaticamente
        if (token != null && token.isNotEmpty && userEmail != null) {
          try {
            final session = await _authService.setSessionWithToken(token, userEmail);
            
            if (session.session != null && session.user != null && mounted) {
              // Login bem-sucedido com passkey!
              try {
                await _authService.supabase.auth.refreshSession();
                
                // Marcar que o usuário tem passkeys e que autenticou com passkey nesta sessão
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('user_has_passkeys_${session.user!.id}', true);
                await prefs.setBool('passkey_authenticated_${session.user!.id}', true);
                
                // Aguardar um pouco para garantir que as flags foram salvas completamente
                await Future.delayed(const Duration(milliseconds: 200));
              } catch (e) {
                // Ignorar erros no refresh
              }
              
              if (!_isDisposed && mounted) {
                // Aguardar um pouco adicional antes de navegar para garantir que tudo foi processado
                await Future.delayed(const Duration(milliseconds: 500));
                
                if (!_isDisposed && mounted) {
                  // Navegar para AuthWrapper usando pushReplacement para evitar loops
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const AuthWrapper(),
                    ),
                  );
                }
              }
              return;
            }
          } catch (e) {
            print('[PasskeyVerification] Erro ao criar sessão: $e');
            if (mounted && !_isDisposed) {
              setState(() {
                _hasError = true;
                _errorMessage = 'Erro ao criar sessão. Tente novamente.';
                _isAuthenticating = false;
              });
            }
            return;
          }
        }
        
        // Se não tivermos token, mostrar erro
        if (mounted && !_isDisposed) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Autenticação bem-sucedida, mas não foi possível criar sessão. Tente novamente.';
            _isAuthenticating = false;
          });
        }
      } else {
        // Verificar se é erro de rate limit
        final errorMessage = result['message'] as String? ?? '';
        final isRateLimit = errorMessage.toLowerCase().contains('muitas tentativas') ||
                           errorMessage.toLowerCase().contains('rate limit') ||
                           errorMessage.toLowerCase().contains('429') ||
                           errorMessage.toLowerCase().contains('too many');
        
        if (mounted && !_isDisposed) {
          setState(() {
            _hasError = true;
            _rateLimitExceeded = isRateLimit;
            _errorMessage = isRateLimit
                ? 'Muitas tentativas de autenticação. Por favor, aguarde alguns minutos antes de tentar novamente.'
                : (errorMessage.isNotEmpty ? errorMessage : 'Erro ao autenticar com passkey. Tente novamente.');
            _isAuthenticating = false;
          });
        }
      }
    } catch (e) {
      if (!mounted || _isDisposed) return;
      
      final errorStr = e.toString().toLowerCase();
      final isRateLimit = errorStr.contains('muitas tentativas') ||
                         errorStr.contains('rate limit') ||
                         errorStr.contains('429') ||
                         errorStr.contains('too many');
      
      setState(() {
        _hasError = true;
        _rateLimitExceeded = isRateLimit;
        _errorMessage = isRateLimit
            ? 'Muitas tentativas de autenticação. Por favor, aguarde alguns minutos antes de tentar novamente.'
            : 'Erro ao autenticar com passkey: ${e.toString()}';
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ícone
                  Icon(
                    Icons.fingerprint,
                    size: 80,
                    color: _rateLimitExceeded ? AppTheme.expenseRed : AppTheme.black,
                  ),
                  const SizedBox(height: 24),
                  
                  // Título
                  Text(
                    _rateLimitExceeded 
                        ? 'Muitas Tentativas'
                        : 'Autenticação com Passkey',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.black,
                        ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Mensagem
                  Text(
                    _rateLimitExceeded
                        ? 'Você tentou autenticar muitas vezes. Por favor, aguarde alguns minutos antes de tentar novamente.'
                        : 'Você tem passkeys configuradas. Por favor, autentique com sua passkey para continuar.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  // Email
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.offWhite,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.email,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Botão de autenticação
                  if (!_rateLimitExceeded) ...[
                    ElevatedButton(
                      onPressed: _isAuthenticating ? null : _authenticateWithPasskey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.black,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isAuthenticating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Autenticar com Passkey',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Mensagem de erro
                  if (_hasError && _errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _rateLimitExceeded 
                            ? AppTheme.expenseRed.withOpacity(0.1)
                            : AppTheme.expenseRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _rateLimitExceeded 
                                  ? AppTheme.expenseRed
                                  : AppTheme.expenseRed,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

