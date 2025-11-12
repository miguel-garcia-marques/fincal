import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../services/wallet_storage_service.dart';
import '../theme/app_theme.dart';

class WalletSelectionDialog extends StatefulWidget {
  const WalletSelectionDialog({super.key});

  @override
  State<WalletSelectionDialog> createState() => _WalletSelectionDialogState();
}

class _WalletSelectionDialogState extends State<WalletSelectionDialog> {
  final WalletService _walletService = WalletService();
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
      final wallets = await _walletService.getAllWallets();
      
      // Filtrar wallets pessoais (isOwner) - pegar apenas a primeira se houver múltiplas
      Wallet? personalWallet;
      final ownedWallets = wallets.where((w) => w.isOwner).toList();
      
      if (ownedWallets.isNotEmpty) {
        // Se houver múltiplas wallets pessoais, usar a primeira (mais antiga)
        // O backend agora garante que não serão criadas novas, mas pode haver duplicatas antigas
        personalWallet = ownedWallets.first;
        
        // Se houver múltiplas, logar para debug
        if (ownedWallets.length > 1) {
          print('⚠️  Múltiplas wallets pessoais encontradas: ${ownedWallets.length}. Usando a primeira: ${personalWallet.id}');
        }
      } else {
        // Não há carteira pessoal, criar uma (o backend retornará a existente se já houver)
        personalWallet = await _walletService.createWallet();
      }
      
      // Garantir que a carteira pessoal está na lista e é a primeira
      // Sempre adicionar a carteira pessoal primeiro
      final walletsList = <Wallet>[personalWallet];
      
      // Adicionar todas as outras carteiras (excluindo wallets pessoais duplicadas)
      for (final wallet in wallets) {
        if (!wallet.isOwner && !walletsList.any((w) => w.id == wallet.id)) {
          walletsList.add(wallet);
        }
      }
      
      // Carregar wallet ativa
      final activeWalletId = await _walletStorageService.getActiveWalletId();
      Wallet? activeWallet;
      
      if (activeWalletId != null) {
        try {
          activeWallet = walletsList.firstWhere((w) => w.id == activeWalletId);
        } catch (e) {
          activeWallet = personalWallet;
        }
      } else {
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
      print('Error loading wallets: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectWallet(Wallet wallet) async {
    await _walletStorageService.setActiveWalletId(wallet.id);
    if (mounted) {
      Navigator.of(context).pop(wallet);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar Carteira'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _wallets.isEmpty
                ? const Text('Nenhuma carteira disponível')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _wallets.length,
                    itemBuilder: (context, index) {
                      final wallet = _wallets[index];
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
                          padding: const EdgeInsets.all(8),
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
                                      style: const TextStyle(
                                        fontSize: 13,
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
                                        child: const Text(
                                          'Minha',
                                          style: TextStyle(
                                            fontSize: 11,
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
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.darkGray,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        if (_selectedWallet != null)
          ElevatedButton(
            onPressed: () => _selectWallet(_selectedWallet!),
            child: const Text('Selecionar'),
          ),
      ],
    );
  }
}

