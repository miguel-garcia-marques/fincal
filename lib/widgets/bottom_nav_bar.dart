import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BottomNavBar extends StatelessWidget {
  final VoidCallback onHistoryTap;
  final VoidCallback onAddTransactionTap;
  final VoidCallback onTransactionsTap;
  final bool isTransactionsActive;

  const BottomNavBar({
    super.key,
    required this.onHistoryTap,
    required this.onAddTransactionTap,
    required this.onTransactionsTap,
    this.isTransactionsActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      margin: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.darkGray,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(
            color: AppTheme.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Histórico (esquerda)
          _NavBarItem(
            icon: Icons.history,
            onTap: onHistoryTap,
            isActive: false,
          ),
          
          // Espaçamento antes do botão central
          const SizedBox(width: 20),
          
          // Adicionar Transação (meio - destacado)
          _NavBarCenterButton(
            onTap: onAddTransactionTap,
          ),
          
          // Espaçamento depois do botão central
          const SizedBox(width: 20),
          
          // Lista de Transações (direita)
          _NavBarItem(
            icon: Icons.receipt_long,
            onTap: onTransactionsTap,
            isActive: isTransactionsActive,
          ),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _NavBarItem({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.darkGray.withOpacity(0.3)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: AppTheme.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _NavBarCenterButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NavBarCenterButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppTheme.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.add,
          color: AppTheme.darkGray,
          size: 28,
        ),
      ),
    );
  }
}
