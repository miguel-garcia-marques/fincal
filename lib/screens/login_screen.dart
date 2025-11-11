import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../utils/responsive_fonts.dart';
import '../theme/app_theme.dart';
import 'email_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _authService = AuthService();
  final _userService = UserService();
  
  bool _isLoading = false;
  bool _isLoginMode = true; // true = login, false = signup
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLoginMode) {
        final response = await _authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
        
        // Verificar se o login foi bem-sucedido
        if (mounted) {
          if (response.user != null && response.session != null) {
            // Verificar se o email foi confirmado
            if (response.user!.emailConfirmedAt == null) {
              // Email não verificado
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor, verifique seu email antes de fazer login.'),
                    backgroundColor: AppTheme.expenseRed,
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            } else {
              // Login bem-sucedido e email verificado
              // Verificar se o usuário existe no MongoDB, se não, criar
              try {
                final existingUser = await _userService.getCurrentUser();
                if (existingUser == null) {
                  // Usuário não existe no MongoDB, criar com email como nome temporário
                  final email = response.user!.email ?? '';
                  final tempName = email.split('@')[0]; // Usar parte antes do @ como nome
                  await _userService.createOrUpdateUser(tempName);
                }
              } catch (e) {
                // Se falhar, continuar mesmo assim
                print('Erro ao verificar/criar usuário no MongoDB: $e');
              }
              
              // Forçar refresh da sessão para garantir que o AuthWrapper detecte
              try {
                await _authService.supabase.auth.refreshSession();
              } catch (_) {
                // Ignorar erros no refresh
              }
              // O AuthWrapper vai detectar a mudança automaticamente via stream
            }
          } else {
            // Login falhou sem erro explícito
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Erro ao fazer login. Verifique suas credenciais.'),
                  backgroundColor: AppTheme.expenseRed,
                ),
              );
            }
          }
        }
      } else {
        final response = await _authService.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
        
        if (mounted) {
          final user = response.user;
          final session = response.session;
          
          if (user != null) {
            // Criar usuário no MongoDB com o nome (se houver sessão temporária)
            // Nota: Se não houver sessão, o usuário será criado quando fizer login pela primeira vez
            if (session != null) {
              try {
                // Criar usuário no MongoDB enquanto temos sessão ativa
                await _userService.createOrUpdateUser(_nameController.text.trim());
              } catch (e) {
                // Se falhar ao criar no MongoDB, continuar mesmo assim
                // O usuário pode ser criado depois quando fizer login
                print('Erro ao criar usuário no MongoDB: $e');
              }
              // Fazer logout para garantir estado limpo (usuário precisa verificar email)
              await _authService.signOut();
            }
            
            // Sempre navegar para tela de verificação quando criar conta
            // A tela de verificação vai verificar se o email já foi confirmado
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => EmailVerificationScreen(
                  email: _emailController.text.trim(),
                ),
              ),
            );
          } else {
            // Erro ao criar usuário, mas não lançou exceção
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro ao criar conta. Tente novamente.'),
                backgroundColor: AppTheme.expenseRed,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Erro desconhecido';
        
        // Tratar erros específicos do Supabase
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('email not confirmed') || 
            errorString.contains('email_not_confirmed') ||
            errorString.contains('email not verified')) {
          errorMessage = 'Por favor, verifique seu email antes de fazer login.';
        } else if (errorString.contains('invalid') || errorString.contains('credentials')) {
          errorMessage = 'Email ou senha incorretos.';
        } else if (_isLoginMode) {
          errorMessage = 'Erro ao fazer login: ${e.toString()}';
        } else {
          errorMessage = 'Erro ao criar conta: ${e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.expenseRed,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;
    
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32.0 : 24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 450 : 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo/Título
                    Icon(
                      Icons.account_balance_wallet,
                      size: isDesktop ? 60 : 80,
                      color: AppTheme.black,
                    ),
                    SizedBox(height: isDesktop ? 16 : 24),
                    Text(
                      'FinCal',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            fontSize: isDesktop 
                                ? ResponsiveFonts.getFontSize(context, 24)
                                : null,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.black,
                          ),
                    ),
                    SizedBox(height: isDesktop ? 32 : 48),
                    
                    // Nome field (apenas no signup)
                    if (!_isLoginMode) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Nome',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: AppTheme.white,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, insira seu nome';
                          }
                          if (value.trim().length < 2) {
                            return 'O nome deve ter pelo menos 2 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Email field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: AppTheme.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira seu email';
                        }
                        if (!value.contains('@')) {
                          return 'Por favor, insira um email válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Password field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: AppTheme.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira sua senha';
                        }
                        if (!_isLoginMode && value.length < 6) {
                          return 'A senha deve ter pelo menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    // Submit button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.black,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
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
                          : Text(
                              _isLoginMode ? 'Entrar' : 'Criar Conta',
                              style: TextStyle(
                                fontSize: ResponsiveFonts.getFontSize(context, 16),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Toggle between login and signup
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _isLoginMode = !_isLoginMode;
                              });
                            },
                      child: Text(
                        _isLoginMode
                            ? 'Não tem uma conta? Criar conta'
                            : 'Já tem uma conta? Fazer login',
                        style: const TextStyle(color: AppTheme.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

