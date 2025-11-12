import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../theme/app_theme.dart';
import '../services/wallet_service.dart';
import '../services/user_service.dart';
import 'wallet_invites_screen.dart';
import '../widgets/wallet_selection_dialog.dart';

class SettingsMenuScreen extends StatefulWidget {
  final Wallet currentWallet;

  const SettingsMenuScreen({
    super.key,
    required this.currentWallet,
  });

  @override
  State<SettingsMenuScreen> createState() => _SettingsMenuScreenState();
}

class _SettingsMenuScreenState extends State<SettingsMenuScreen> {
  final WalletService _walletService = WalletService();
  final UserService _userService = UserService();
  
  String? _ownerName;
  bool _isLoadingOwner = false;
  String? _currentUserName;
  bool _isLoadingUserName = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserName();
    if (!widget.currentWallet.isOwner) {
      _loadOwnerName();
    }
  }

  Future<void> _loadCurrentUserName() async {
    setState(() {
      _isLoadingUserName = true;
    });
    
    try {
      final user = await _userService.getCurrentUser();
      if (mounted) {
        setState(() {
          _currentUserName = user?.name ?? 'Usuário';
          _isLoadingUserName = false;
        });
      }
    } catch (e) {
      print('Erro ao carregar nome do usuário: $e');
      if (mounted) {
        setState(() {
          _currentUserName = 'Usuário';
          _isLoadingUserName = false;
        });
      }
    }
  }

  Future<void> _loadOwnerName() async {
    setState(() {
      _isLoadingOwner = true;
    });
    
    try {
      // Buscar membros da wallet para obter o nome do dono
      final members = await _walletService.getWalletMembers(widget.currentWallet.id);
      final owner = members.firstWhere((m) => m.isOwner, orElse: () => members.first);
      
      if (mounted) {
        setState(() {
          _ownerName = owner.name ?? 'Usuário';
          _isLoadingOwner = false;
        });
      }
    } catch (e) {
      print('Erro ao carregar nome do dono: $e');
      if (mounted) {
        setState(() {
          _ownerName = 'Usuário';
          _isLoadingOwner = false;
        });
      }
    }
  }

  Future<void> _showWalletSelection() async {
    final selectedWallet = await showDialog<Wallet>(
      context: context,
      builder: (context) => const WalletSelectionDialog(),
    );

    if (selectedWallet != null && mounted) {
      // Recarregar a tela para refletir a mudança
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Definições'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: AppTheme.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Saudação
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _isLoadingUserName 
                  ? 'Olá...' 
                  : 'Olá, ${_currentUserName ?? 'Usuário'}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.black,
                  ),
            ),
          ),
          // Carteira atual
          Card(
            elevation: 2,
            child: InkWell(
              onTap: _showWalletSelection,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Carteira atual',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.currentWallet.isOwner
                                ? 'Pessoal'
                                : (_isLoadingOwner ? 'Carregando...' : _ownerName ?? 'Usuário'),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Menu de opções
          _buildMenuOption(
            context,
            icon: Icons.people,
            title: 'Convites',
            subtitle: 'Gerir convites e membros',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => WalletInvitesScreen(
                    currentWallet: widget.currentWallet,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          
          // Placeholder para futuras opções
          _buildMenuOption(
            context,
            icon: Icons.settings,
            title: 'Preferências',
            subtitle: 'Em breve',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Funcionalidade em desenvolvimento')),
              );
            },
            enabled: false,
          ),
          const SizedBox(height: 12),
          
          _buildMenuOption(
            context,
            icon: Icons.notifications,
            title: 'Notificações',
            subtitle: 'Em breve',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Funcionalidade em desenvolvimento')),
              );
            },
            enabled: false,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: enabled
                      ? AppTheme.primaryColor.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: enabled ? AppTheme.primaryColor : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: enabled ? null : Colors.grey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: enabled ? Colors.grey[600] : Colors.grey,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled ? Colors.grey : Colors.grey[300],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

