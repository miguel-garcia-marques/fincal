import 'package:flutter/material.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';
import 'custom_calendar_picker.dart';

class PeriodSelectorDialog extends StatefulWidget {
  final int selectedYear;
  final DateTime startDate;
  final DateTime endDate;

  const PeriodSelectorDialog({
    super.key,
    required this.selectedYear,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<PeriodSelectorDialog> createState() => _PeriodSelectorDialogState();
}

class _PeriodSelectorDialogState extends State<PeriodSelectorDialog> {
  late int _selectedYear;
  late DateTime _startDate;
  late DateTime _endDate;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.selectedYear;
    _startDate = widget.startDate;
    _endDate = widget.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectYear() async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) {
        final currentYear = DateTime.now().year;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppTheme.black,
                  onPrimary: AppTheme.white,
                ),
          ),
          child: AlertDialog(
            title: const Text('Selecionar Ano'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ListView.builder(
                itemCount: 50,
                itemBuilder: (context, index) {
                  final year = currentYear - 25 + index;
                  return ListTile(
                    title: Text('$year'),
                    selected: year == _selectedYear,
                    onTap: () => Navigator.of(context).pop(year),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedYear = picked;
        _updateDatesForYear();
      });
    }
  }

  void _updateDatesForYear() {
    final now = DateTime.now();
    if (_selectedYear == now.year) {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
    } else {
      _startDate = DateTime(_selectedYear, 1, 1);
      _endDate = DateTime(_selectedYear, 1, 31);
    }
    setState(() {});
  }

  Future<void> _selectDateRange() async {
    final result = await showDialog<Map<String, DateTime>>(
      context: context,
      builder: (context) => CustomCalendarPicker(
        initialStartDate: _startDate,
        initialEndDate: _endDate,
        initialYear: _selectedYear,
      ),
    );

    if (result != null) {
      setState(() {
        _startDate = result['startDate']!;
        _endDate = result['endDate']!;
        // Atualizar o ano se necessário
        if (_startDate.year != _selectedYear) {
          _selectedYear = _startDate.year;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Selecionar Período',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Ano
            InkWell(
              onTap: _selectYear,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.darkGray.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ano',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.darkGray,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_selectedYear',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.black,
                              ),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_drop_down, color: AppTheme.black),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Período
            InkWell(
              onTap: _selectDateRange,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.darkGray.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Período',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.darkGray,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatDate(_startDate)} - ${formatDate(_endDate)}',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.black,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: AppTheme.black),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Nome do período
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nome do período (opcional)',
                hintText: 'Ex: Janeiro 2024, Férias, etc.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(16),
                filled: true,
                fillColor: AppTheme.white,
              ),
            ),
            const SizedBox(height: 20),
            // Botões
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop({
                        'year': _selectedYear,
                        'startDate': _startDate,
                        'endDate': _endDate,
                        'name': _nameController.text.trim(),
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.black,
                      foregroundColor: AppTheme.white,
                    ),
                    child: const Text('Confirmar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

