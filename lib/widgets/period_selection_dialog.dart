import 'package:flutter/material.dart';
import '../models/period_history.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';
import 'period_selector_dialog.dart';

class PeriodSelectionDialog extends StatefulWidget {
  final List<PeriodHistory> pastPeriods;
  final int currentYear;

  const PeriodSelectionDialog({
    super.key,
    required this.pastPeriods,
    required this.currentYear,
  });

  @override
  State<PeriodSelectionDialog> createState() => _PeriodSelectionDialogState();
}

class _PeriodSelectionDialogState extends State<PeriodSelectionDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selecionar Período',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (widget.pastPeriods.isNotEmpty) ...[
              Text(
                'Períodos anteriores:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.darkGray,
                    ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.pastPeriods.length,
                  itemBuilder: (context, index) {
                    final period = widget.pastPeriods[index];
                    return InkWell(
                      onTap: () {
                        Navigator.of(context).pop({
                          'type': 'existing',
                          'period': period,
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.darkGray.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (period.name.isNotEmpty)
                                    Text(
                                      period.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  if (period.name.isNotEmpty) const SizedBox(height: 4),
                                  Text(
                                '${formatDate(period.startDate)} - ${formatDate(period.endDate)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                          fontWeight: period.name.isNotEmpty ? FontWeight.normal : FontWeight.w500,
                                        ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: AppTheme.darkGray,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
            ],
            ElevatedButton.icon(
              onPressed: () async {
                final result = await showDialog(
                  context: context,
                  builder: (context) => PeriodSelectorDialog(
                    selectedYear: widget.currentYear,
                    startDate: DateTime(
                      widget.currentYear,
                      DateTime.now().month,
                      1,
                    ),
                    endDate: DateTime(
                      widget.currentYear,
                      DateTime.now().month + 1,
                      0,
                    ),
                  ),
                );

                if (result != null && mounted) {
                  Navigator.of(context).pop({
                    'type': 'new',
                    'year': result['year'],
                    'startDate': result['startDate'],
                    'endDate': result['endDate'],
                    'name': result['name'] ?? '',
                  });
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Criar Novo Período'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.black,
                foregroundColor: AppTheme.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
