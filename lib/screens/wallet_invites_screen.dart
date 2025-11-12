import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/wallet.dart';
import '../models/invite.dart';
import '../models/wallet_member.dart';
import '../services/wallet_service.dart';
import '../theme/app_theme.dart';

class WalletInvitesScreen extends StatefulWidget {
  final Wallet currentWallet;

  const WalletInvitesScreen({
    super.key,
    required this.currentWallet,
  });

  @override
  State<WalletInvitesScreen> createState() => _WalletInvitesScreenState();
}

class _WalletInvitesScreenState extends State<WalletInvitesScreen> {
  final WalletService _walletService = WalletService();
  
  List<Invite> _invites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final invites = await _walletService.getWalletInvites(
        widget.currentWallet.id,
        forceRefresh: forceRefresh,
      );
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

  Future<void> _createInviteLink() async {
    String selectedPermission = 'read';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Criar Link de Convite'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: 'read',
                decoration: const InputDecoration(
                  labelText: 'Permissão',
                  prefixIcon: Icon(Icons.security),
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
                  setDialogState(() {
                    selectedPermission = value ?? 'read';
                  });
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
              onPressed: () => Navigator.of(context).pop(selectedPermission),
              child: const Text('Criar Link'),
            ),
          ],
        ),
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
          // Usar query parameter para compatibilidade com Flutter web
          final inviteUrl = '${Uri.base.origin}/invite.html?token=${invite.token}';
          await _showInviteDialog(inviteUrl, invite);
          _loadInvites(forceRefresh: true);
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

  Future<void> _showInviteDialog(String inviteUrl, Invite invite) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Convite Criado',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: QrImageView(
                      data: inviteUrl,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  const Text(
                    'Escaneie o QR code ou compartilhe o link',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  
                  // Link
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            inviteUrl,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: inviteUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link copiado!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Informações do convite
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Permissão: ${invite.permission == 'read' ? 'Apenas Visualizar' : 'Criar Transações'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    child: const Text('Fechar'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Future<void> _changePermission(Invite invite) async {
    if (invite.acceptedBy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro: Usuário não encontrado')),
      );
      return;
    }

    // Buscar o membro atual para saber a permissão atual
    List<WalletMember> members;
    try {
      members = await _walletService.getWalletMembers(widget.currentWallet.id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar membros: $e')),
      );
      return;
    }

    final memberIndex = members.indexWhere(
      (m) => m.userId == invite.acceptedBy && !m.isOwner,
    );

    if (memberIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membro não encontrado')),
      );
      return;
    }

    final member = members[memberIndex];
    final currentPermission = member.permission;

    // Mostrar diálogo para escolher nova permissão
    String? selectedPermission = currentPermission;
    final newPermission = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Mudar Permissão'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Usuário: ${invite.acceptedByName ?? invite.acceptedBy}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text('Permissão atual:'),
              Text(
                currentPermission == 'read' ? 'Apenas Visualizar' : 'Criar Transações',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Nova permissão:'),
              const SizedBox(height: 8),
              RadioListTile<String>(
                title: const Text('Apenas Visualizar'),
                value: 'read',
                groupValue: selectedPermission,
                onChanged: (value) {
                  setState(() {
                    selectedPermission = value;
                  });
                },
              ),
              RadioListTile<String>(
                title: const Text('Criar Transações'),
                value: 'write',
                groupValue: selectedPermission,
                onChanged: (value) {
                  setState(() {
                    selectedPermission = value;
                  });
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
              onPressed: () => Navigator.of(context).pop(selectedPermission),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );

    if (newPermission != null && newPermission != currentPermission) {
      try {
        await _walletService.updateMemberPermission(
          widget.currentWallet.id,
          invite.acceptedBy!,
          newPermission,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Permissão alterada para: ${newPermission == 'read' ? 'Apenas Visualizar' : 'Criar Transações'}',
              ),
            ),
          );
          _loadInvites(forceRefresh: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao alterar permissão: $e')),
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
        await _walletService.cancelInvite(token, widget.currentWallet.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Convite cancelado')),
          );
          _loadInvites(forceRefresh: true);
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
        title: const Text('Convites'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: AppTheme.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ações de convite (apenas para donos)
                  if (widget.currentWallet.isOwner) ...[
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Criar Convite',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _createInviteLink,
                                icon: const Icon(Icons.qr_code),
                                label: const Text('Criar Link de Convite'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Lista de convites
                  Text(
                    'Convites Ativos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_invites.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhum convite criado',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _invites.length,
                      itemBuilder: (context, index) {
                        final invite = _invites[index];
                        return _buildInviteListItem(invite);
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildInviteListItem(Invite invite) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: ListTile(
        leading: Icon(
          Icons.link,
          color: invite.isExpired
              ? Colors.red
              : invite.status == 'accepted'
                  ? Colors.green
                  : Colors.grey[700],
        ),
        title: Text(
          'Link de Convite',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Permissão: ${invite.permission == 'read' ? 'Apenas Visualizar' : 'Criar Transações'}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            if (invite.status == 'accepted' && invite.acceptedByName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Aceito por: ${invite.acceptedByName}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: invite.isExpired
                    ? Colors.red.withOpacity(0.1)
                    : invite.status == 'accepted'
                        ? Colors.green.withOpacity(0.1)
                        : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                invite.isExpired
                    ? 'Expirado'
                    : invite.status == 'accepted'
                        ? 'Aceito'
                        : 'Pendente',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: invite.isExpired
                      ? Colors.red
                      : invite.status == 'accepted'
                          ? Colors.green
                          : Colors.blue,
                ),
              ),
            ),
          ],
        ),
        trailing: widget.currentWallet.isOwner
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botão para mudar permissão (apenas para invites aceitos)
                  if (invite.status == 'accepted' && invite.acceptedBy != null)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      color: AppTheme.black,
                      tooltip: 'Mudar permissão',
                      onPressed: () => _changePermission(invite),
                    ),
                  // Botão para cancelar convite
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: AppTheme.expenseRed,
                    tooltip: 'Cancelar convite',
                    onPressed: () => _cancelInvite(invite.token),
                  ),
                ],
              )
            : null,
        onTap: () {
          // Mostrar detalhes do convite
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Link de Convite'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    'Permissão',
                    invite.permission == 'read'
                        ? 'Apenas Visualizar'
                        : 'Criar Transações',
                  ),
                  _buildInfoRow(
                    'Status',
                    invite.isExpired
                        ? 'Expirado'
                        : invite.status == 'accepted'
                            ? 'Aceito'
                            : 'Pendente',
                  ),
                  if (invite.status == 'accepted' && invite.acceptedByName != null)
                    _buildInfoRow(
                      'Aceito por',
                      invite.acceptedByName!,
                    ),
                  _buildInfoRow(
                    'Criado em',
                    '${invite.createdAt.day}/${invite.createdAt.month}/${invite.createdAt.year}',
                  ),
                  _buildInfoRow(
                    'Expira em',
                    '${invite.expiresAt.day}/${invite.expiresAt.month}/${invite.expiresAt.year}',
                  ),
                  if (invite.acceptedAt != null)
                    _buildInfoRow(
                      'Aceito em',
                      '${invite.acceptedAt!.day}/${invite.acceptedAt!.month}/${invite.acceptedAt!.year}',
                    ),
                ],
              ),
              actions: [
                if (widget.currentWallet.isOwner)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _cancelInvite(invite.token);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.expenseRed,
                    ),
                    child: const Text('Cancelar Convite'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
