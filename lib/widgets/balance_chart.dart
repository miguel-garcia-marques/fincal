import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

class BalanceChart extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final Map<DateTime, double> dailyBalances;
  final double initialBalance;

  const BalanceChart({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.dailyBalances,
    required this.initialBalance,
  });

  @override
  Widget build(BuildContext context) {
    final days = getDaysInRange(startDate, endDate);
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    // Calcular saldo acumulado para cada dia
    final List<MapEntry<DateTime, double>> balanceData = [];
    double runningBalance = initialBalance;

    for (var day in days) {
      final dayOnly = DateTime(day.year, day.month, day.day);
      final dayBalance = dailyBalances[dayOnly] ?? 0.0;
      runningBalance += dayBalance;
      balanceData.add(MapEntry(dayOnly, runningBalance));
    }

    if (balanceData.isEmpty) {
      return const SizedBox.shrink();
    }

    // Encontrar valores min e max para escala
    final balances = balanceData.map((e) => e.value).toList();
    final minBalance = balances.reduce((a, b) => a < b ? a : b);
    final maxBalance = balances.reduce((a, b) => a > b ? a : b);
    final range = (maxBalance - minBalance).abs();
    // Se todos os valores forem iguais, criar um range mínimo para visualização
    final padding = range > 0 ? range * 0.1 : 10.0; // 10% de padding ou mínimo de 10
    final chartMin = minBalance - padding;
    final chartMax = maxBalance + padding;
    final chartRange = (chartMax - chartMin).abs();

    // Determinar se há valores positivos e negativos
    final hasPositive = maxBalance > 0;
    final hasNegative = minBalance < 0;
    final zeroLine = hasPositive && hasNegative
        ? (0 - chartMin) / chartRange
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calcular altura baseada na altura da janela
        final screenHeight = MediaQuery.of(context).size.height;
        // Usar aproximadamente 12-15% da altura da tela, com mínimo de 80 e máximo de 200
        final calculatedHeight = (screenHeight * 0.13).clamp(80.0, 200.0);
        
        return Container(
          height: calculatedHeight,
          width: double.infinity,
          child: CustomPaint(
            painter: _BalanceChartPainter(
              balanceData: balanceData,
              chartMin: chartMin,
              chartMax: chartMax,
              zeroLine: zeroLine,
            ),
            child: Container(),
          ),
        );
      },
    );
  }

}

class _BalanceChartPainter extends CustomPainter {
  final List<MapEntry<DateTime, double>> balanceData;
  final double chartMin;
  final double chartMax;
  final double? zeroLine;

  _BalanceChartPainter({
    required this.balanceData,
    required this.chartMin,
    required this.chartMax,
    required this.zeroLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (balanceData.isEmpty || size.width == 0 || size.height == 0) return;

    final chartRange = (chartMax - chartMin).abs();
    if (chartRange == 0) {
      // Se todos os valores são iguais, desenhar uma linha horizontal
      final y = size.height / 2;
      final paint = Paint()
        ..color = AppTheme.darkGray
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill;

    // Desenhar linha de zero se necessário
    if (zeroLine != null) {
      final zeroY = size.height * (1 - zeroLine!);
      final zeroLinePaint = Paint()
        ..color = AppTheme.darkGray.withOpacity(0.2)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, zeroY),
        Offset(size.width, zeroY),
        zeroLinePaint,
      );
    }

    // Preparar pontos do gráfico
    final points = <Offset>[];
    for (var i = 0; i < balanceData.length; i++) {
      final value = balanceData[i].value;
      final normalizedValue = (value - chartMin) / chartRange;
      final x = (i / (balanceData.length - 1)) * size.width;
      final y = size.height * (1 - normalizedValue);
      points.add(Offset(x, y));
    }

    // Desenhar área preenchida
    if (points.length > 1) {
      final path = Path();
      path.moveTo(points.first.dx, size.height);
      for (var point in points) {
        path.lineTo(point.dx, point.dy);
      }
      path.lineTo(points.last.dx, size.height);
      path.close();

      // Cor do preenchimento em tons de cinza
      fillPaint.color = AppTheme.darkGray.withOpacity(0.1);
      canvas.drawPath(path, fillPaint);
    }

    // Desenhar linha do gráfico
    if (points.length > 1) {
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        // Usar curvas suaves
        if (i == 1) {
          path.lineTo(points[i].dx, points[i].dy);
        } else {
          final prevPoint = points[i - 1];
          final currentPoint = points[i];
          final controlPoint = Offset(
            (prevPoint.dx + currentPoint.dx) / 2,
            (prevPoint.dy + currentPoint.dy) / 2,
          );
          path.quadraticBezierTo(
            prevPoint.dx,
            prevPoint.dy,
            controlPoint.dx,
            controlPoint.dy,
          );
          path.lineTo(currentPoint.dx, currentPoint.dy);
        }
      }

      // Cor da linha em tons de cinza
      paint.color = AppTheme.darkGray;

      canvas.drawPath(path, paint);
    }

    // Desenhar pontos nos dados
    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppTheme.darkGray;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      canvas.drawCircle(point, 3, pointPaint);
      // Círculo branco interno
      canvas.drawCircle(point, 1.5, Paint()..color = AppTheme.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

