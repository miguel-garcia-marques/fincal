import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../services/user_service.dart';
import '../services/wallet_storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_fonts.dart';
import 'home_screen.dart';

class WalletSelectionScreen extends StatefulWidget {
  const WalletSelectionScreen({super.key});

  @override
  State<WalletSelectionScreen> createState() => _WalletSelectionScreenState();
}

class _WalletSelectionScreenState extends State<WalletSelectionScreen> {
  final WalletService _walletService = WalletService();
  final UserService _userService = UserService();
  final WalletStorageService _walletStorageService = WalletStorageService();
  
  List<Wallet> _wallets = [];
  bool _isLoading = true;
  Wallet? _selectedWallet;

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    setState(() => _isLoading = true);
    try {
      // Carregar dados do usuário
      final user = await _userService.getCurrentUser();
      if (user == null) {
        // Se não houver usuário, ir direto para home (será criado lá)
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
        return;
      }

      // Carregar todas as wallets
      final wallets = await _walletService.getAllWallets();
      
      // Separar wallet pessoal e wallets convidadas
      Wallet? personalWallet;
      List<Wallet> invitedWallets = [];
      
      // Filtrar wallets pessoais - pegar apenas a primeira se houver múltiplas
      final ownedWallets = wallets.where((w) => w.isOwner).toList();
      
      if (ownedWallets.isNotEmpty) {
        // Se houver múltiplas wallets pessoais, usar a primeira (mais antiga)
        // O backend agora garante que não serão criadas novas, mas pode haver duplicatas antigas
        personalWallet = ownedWallets.first;
        
        // Se houver múltiplas, logar para debug
        if (ownedWallets.length > 1) {

        }
      }
      
      // Separar wallets convidadas
      for (final wallet in wallets) {
        if (!wallet.isOwner) {
          invitedWallets.add(wallet);
        }
      }

      // Se não houver wallet pessoal, criar uma (o backend retornará a existente se já houver)
      if (personalWallet == null) {
        personalWallet = await _walletService.createWallet();
      }

      // Montar lista: wallet pessoal primeiro, depois convidadas
      final walletsList = <Wallet>[personalWallet];
      walletsList.addAll(invitedWallets);

      // Verificar se há wallet ativa salva
      final activeWalletId = await _walletStorageService.getActiveWalletId();
      Wallet? activeWallet;

      if (activeWalletId != null) {
        try {
          activeWallet = walletsList.firstWhere((w) => w.id == activeWalletId);
        } catch (e) {
          activeWallet = personalWallet;
        }
      } else {
        // Se não houver wallet ativa e houver apenas a pessoal, usar ela automaticamente
        if (walletsList.length == 1) {
          await _walletStorageService.setActiveWalletId(personalWallet.id);
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
          return;
        }
        activeWallet = personalWallet;
      }

      if (mounted) {
        setState(() {
          _wallets = walletsList;
          _selectedWallet = activeWallet;
          _isLoading = false;
        });
      }
    } catch (e) {

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar wallets: $e'),
            backgroundColor: AppTheme.expenseRed,
          ),
        );
      }
    }
  }

  Future<void> _selectWallet(Wallet wallet) async {
    await _walletStorageService.setActiveWalletId(wallet.id);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;

    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isDesktop ? 32.0 : 24.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isDesktop ? 600 : 500),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Título
                        Icon(
                          Icons.account_balance_wallet,
                          size: isDesktop ? 60 : 80,
                          color: AppTheme.black,
                        ),
                        SizedBox(height: isDesktop ? 16 : 24),
                        Text(
                          'Selecionar Carteira',
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
                        
                        // Lista de wallets
                        if (_wallets.isEmpty)
                          const Text(
                            'Nenhuma carteira disponível',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.darkGray),
                          )
                        else
                          ..._wallets.map((wallet) {
                            final isSelected = _selectedWallet?.id == wallet.id;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedWallet = wallet;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                        : AppTheme.lighterGray.withOpacity(0.3),
                                    width: isSelected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  color: isSelected
                                      ? AppTheme.primaryColor.withOpacity(0.05)
                                      : AppTheme.white,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            wallet.ownerName ?? 'Usuário',
                                            style: TextStyle(
                                              fontSize: ResponsiveFonts.getFontSize(context, 13),
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.black,
                                            ),
                                          ),
                                          if (wallet.isOwner) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColor.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Minha',
                                                style: TextStyle(
                                                  fontSize: ResponsiveFonts.getFontSize(context, 11),
                                                  color: AppTheme.primaryColor,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 2),
                                          Text(
                                            wallet.permission == 'read'
                                                ? 'Visualização'
                                                : wallet.permission == 'write'
                                                    ? 'Edição'
                                                    : 'Proprietário',
                                            style: TextStyle(
                                              fontSize: ResponsiveFonts.getFontSize(context, 13),
                                              color: AppTheme.darkGray,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: AppTheme.primaryColor,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        
                        const SizedBox(height: 16),
                        
                        // Botão de selecionar
                        if (_selectedWallet != null)
                          ElevatedButton(
                            onPressed: () => _selectWallet(_selectedWallet!),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.black,
                              foregroundColor: AppTheme.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Selecionar e Entrar',
                              style: TextStyle(
                                fontSize: ResponsiveFonts.getFontSize(context, 16),
                                fontWeight: FontWeight.w600,
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
