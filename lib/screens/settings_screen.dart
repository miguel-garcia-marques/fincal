import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wallet.dart';
import '../models/invite.dart';
import '../services/wallet_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final Wallet currentWallet;

  const SettingsScreen({
    super.key,
    required this.currentWallet,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final WalletService _walletService = WalletService();
  final AuthService _authService = AuthService();
  
  List<Invite> _invites = [];
  bool _isLoading = true;
  String _selectedPermission = 'read';

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    setState(() => _isLoading = true);
    try {
      final invites = await _walletService.getWalletInvites(widget.currentWallet.id);
      if (mounted) {
        setState(() {
          _invites = invites;
          _isLoading = false;
        });
      }
    } catch (e) {

      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createInviteByEmail() async {
    final emailController = TextEditingController();
    final permissionController = TextEditingController(text: 'read');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convidar por Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'email@exemplo.com',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: 'read',
              decoration: const InputDecoration(
                labelText: 'Permissão',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'read',
                  child: Text('Apenas Visualizar'),
                ),
                DropdownMenuItem(
                  value: 'write',
                  child: Text('Criar Transações'),
                ),
              ],
              onChanged: (value) {
                permissionController.text = value ?? 'read';
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (emailController.text.isNotEmpty) {
                Navigator.of(context).pop({
                  'email': emailController.text,
                  'permission': permissionController.text,
                });
              }
            },
            child: const Text('Convidar'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _walletService.createInvite(
          walletId: widget.currentWallet.id,
          email: result['email'],
          permission: result['permission'] ?? 'read',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Convite enviado com sucesso!')),
          );
          _loadInvites();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao criar convite: $e')),
          );
        }
      }
    }
  }

  Future<void> _createInviteLink() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Criar Link de Convite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: 'read',
              decoration: const InputDecoration(
                labelText: 'Permissão',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'read',
                  child: Text('Apenas Visualizar'),
                ),
                DropdownMenuItem(
                  value: 'write',
                  child: Text('Criar Transações'),
                ),
              ],
              onChanged: (value) {
                _selectedPermission = value ?? 'read';
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_selectedPermission),
            child: const Text('Criar Link'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final invite = await _walletService.createInvite(
          walletId: widget.currentWallet.id,
          email: null,
          permission: result,
        );
        
        if (mounted) {
          final inviteUrl = '${Uri.base.origin}/invite/${invite.token}';
          
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Link de Convite Criado'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Compartilhe este link:'),
                  const SizedBox(height: 8),
                  SelectableText(
                    inviteUrl,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inviteUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copiado!')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar Link'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          );
          _loadInvites();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao criar convite: $e')),
          );
        }
      }
    }
  }

  Future<void> _cancelInvite(String token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Convite'),
        content: const Text('Tem certeza que deseja cancelar este convite?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.expenseRed,
            ),
            child: const Text('Sim'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _walletService.cancelInvite(token);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Convite cancelado')),
          );
          _loadInvites();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao cancelar convite: $e')),
          );
        }
      }
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informações da Wallet
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Carteira Calendário',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.currentWallet.name,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (widget.currentWallet.isOwner)
                      Chip(
                        label: const Text('Dono'),
                        backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Secção de Convites
            Text(
              'Convites',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            
            if (widget.currentWallet.isOwner) ...[
              // Botões para criar convites
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _createInviteByEmail,
                      icon: const Icon(Icons.email),
                      label: const Text('Convidar por Email'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _createInviteLink,
                      icon: const Icon(Icons.link),
                      label: const Text('Criar Link'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            
            // Lista de convites
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_invites.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text('Nenhum convite criado'),
                  ),
                ),
              )
            else
              ..._invites.map((invite) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    invite.email ?? 'Link de Convite',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Permissão: ${invite.permission == 'read' ? 'Apenas Visualizar' : 'Criar Transações'}'),
                      Text('Status: ${invite.status}'),
                      if (invite.isExpired)
                        const Text(
                          'Expirado',
                          style: TextStyle(color: Colors.red),
                        ),
                    ],
                  ),
                  trailing: widget.currentWallet.isOwner
                      ? IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _cancelInvite(invite.token),
                        )
                      : null,
                ),
              )),
          ],
        ),
      ),
    );
  }
}
