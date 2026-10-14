// Gráfico de barras "ganho por dia da semana" desenhado à mão (sem
// biblioteca de gráficos), usado na aba Financeiro.
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Recebe o ganho de cada dia da semana (1=Segunda...7=Domingo) e desenha
/// as barrinhas com os valores.
class WeeklyBarChart extends StatelessWidget {
  final Map<int, double> earnings;

  const WeeklyBarChart({super.key, required this.earnings});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: CustomPaint(
        painter: _BarChartPainter(earnings: earnings),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Faz o desenho de verdade do gráfico (linhas de grade, barras e legendas)
/// direto no canvas.
class _BarChartPainter extends CustomPainter {
  final Map<int, double> earnings;

  _BarChartPainter({required this.earnings});

  /// Arredonda o valor máximo do eixo Y pra um número "bonito" (tipo 100,
  /// 200, 500, 1000...) em vez de um número quebrado, pra ficar mais fácil
  /// de ler as linhas de grade.
  double _niceMax(double maxVal) {
    if (maxVal == 0) return 800;
    final magnitude = math.pow(10, (math.log(maxVal) / math.ln10).floor()).toDouble();
    final normalized = maxVal / magnitude;
    double nice;
    if (normalized <= 1) {
      nice = 1;
    } else if (normalized <= 2) {
      nice = 2;
    } else if (normalized <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  /// Desenha as linhas de grade horizontais com os valores no eixo Y, e
  /// depois uma barra por dia da semana (Seg a Dom) com o ganho daquele dia.
  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 40.0;
    const bottomPad = 25.0;
    const topPad = 8.0;

    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad - topPad;

    final maxVal = earnings.values.fold(0.0, math.max);
    final chartMax = _niceMax(maxVal);
    final step = chartMax / 4;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.3),
      fontSize: 10,
    );

    final dayLabelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.38),
      fontSize: 11,
    );

    // Horizontal dashed lines
    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH - (i / 4) * chartH;
      const dashWidth = 4.0;
      const dashSpace = 4.0;
      double x = leftPad;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dashWidth, size.width), y),
          gridPaint,
        );
        x += dashWidth + dashSpace;
      }

      // Y-axis label
      final labelValue = step * i;
      final labelText = labelValue >= 1000
          ? '${(labelValue / 1000).toStringAsFixed(1)}k'
          : labelValue.toStringAsFixed(0);
      final tp = TextPainter(
        text: TextSpan(text: labelText, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // Bars
    const days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    final barWidth = (chartW / 7) * 0.55;
    final barSpacing = chartW / 7;

    final barPaint = Paint()..color = Colors.blue;

    for (int i = 1; i <= 7; i++) {
      final value = earnings[i] ?? 0;
      final barH = chartMax > 0 ? (value / chartMax) * chartH : 0.0;
      final x = leftPad + (i - 1) * barSpacing + (barSpacing - barWidth) / 2;
      final y = topPad + chartH - barH;

      if (barH > 0) {
        final rrect = RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barWidth, barH),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(rrect, barPaint);
      } else {
        // Draw a tiny sliver so empty days show something
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, topPad + chartH - 2, barWidth, 2),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
          ),
          barPaint..color = Colors.blue.withValues(alpha: 0.2),
        );
        barPaint.color = Colors.blue;
      }

      // Day label
      final tp = TextPainter(
        text: TextSpan(text: days[i - 1], style: dayLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x + barWidth / 2 - tp.width / 2, size.height - bottomPad + 4),
      );
    }
  }

  /// Só redesenha o gráfico se os valores de ganho mudarem.
  @override
  bool shouldRepaint(_BarChartPainter old) => old.earnings != earnings;
}
