import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String? inviteToken;
  
  const EmailVerificationScreen({
    super.key,
    required this.email,
    this.inviteToken,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _authService = AuthService();
  bool _isChecking = false;
  bool _isVerified = false;
  bool _hasError = false;
  String? _errorMessage;
  int _resendCooldown = 0; // Contador de cooldown em segundos
  bool _isDisposed = false; // Flag para controlar se o widget foi descartado

  @override
  void initState() {
    super.initState();
    // Não verificar automaticamente - o usuário deve clicar em "já verifiquei"
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _checkVerificationAndNavigate() async {
    if (_isChecking || _isDisposed || !mounted) return;
    
    setState(() {
      _isChecking = true;
      _hasError = false;
    });

    try {
      // Simplesmente redirecionar para login
      // O usuário pode tentar fazer login e será informado se o email não foi verificado
      // Não tentar verificar aqui para evitar erros desnecessários
      if (!_isDisposed && mounted) {
        setState(() {
          _isChecking = false;
        });
        
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => LoginScreen(inviteToken: widget.inviteToken),
          ),
        );
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() {
          _isChecking = false;
          _hasError = true;
          _errorMessage = 'Erro ao navegar: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_resendCooldown > 0 || _isDisposed || !mounted) return; // Ainda em cooldown
    
    setState(() {
      _isChecking = true;
      _hasError = false;
    });

    try {
      await _authService.supabase.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      
      if (!_isDisposed && mounted) {
        // Iniciar cooldown de 60 segundos
        setState(() {
          _resendCooldown = 60;
          _isChecking = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email de verificação reenviado!'),
            backgroundColor: AppTheme.incomeGreen,
          ),
        );
        
        // Iniciar countdown
        _startCooldown();
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Erro ao reenviar email: ${e.toString()}';
          _isChecking = false;
        });
      }
    }
  }

  void _startCooldown() {
    if (_resendCooldown <= 0 || _isDisposed) return;
    
    Future.delayed(const Duration(seconds: 1), () {
      if (!_isDisposed && mounted && _resendCooldown > 0) {
        setState(() {
          _resendCooldown--;
        });
        _startCooldown();
      }
    });
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
                    _isVerified ? Icons.check_circle : Icons.email_outlined,
                    size: 80,
                    color: _isVerified ? AppTheme.incomeGreen : AppTheme.black,
                  ),
                  const SizedBox(height: 24),
                  
                  // Título
                  Text(
                    _isVerified ? 'Email Verificado!' : 'Verifique seu Email',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.black,
                        ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Mensagem
                  Text(
                    _isVerified
                        ? 'Seu email foi verificado com sucesso! Redirecionando...'
                        : 'Enviamos um link de verificação para:',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (!_isVerified) ...[
                    const SizedBox(height: 8),
                    Text(
                      '⚠️ Sua conta só ficará ativa após verificação',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.darkGray,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ],
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
                  
                  // Instruções
                  if (!_isVerified) ...[
                    Text(
                      'Por favor, verifique sua caixa de entrada e clique no link de confirmação no email que enviamos.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.darkGray,
                          ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Botão "Já verifiquei"
                    ElevatedButton(
                      onPressed: _isChecking ? null : _checkVerificationAndNavigate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.black,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isChecking
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
                              'Já Verifiquei',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Botão reenviar com countdown
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Countdown acima do botão
                        if (_resendCooldown > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Aguarde ${_resendCooldown}s para reenviar',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.darkGray,
                                  ),
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: (_isChecking || _resendCooldown > 0) 
                              ? null 
                              : _resendVerificationEmail,
                          icon: _isChecking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(
                            _resendCooldown > 0 
                                ? 'Reenviar Email (${_resendCooldown}s)'
                                : 'Reenviar Email',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  // Error message
                  if (_hasError && _errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.expenseRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.expenseRed,
                              ),
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

