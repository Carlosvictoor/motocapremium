// Gráfico de barras "gasto por dia do mês", usado no resumo de gastos da
// aba Financeiro — mesmo padrão visual do gráfico "Resumo da semana"
// (ver weekly_bar_chart.dart): grade horizontal com valores no eixo Y,
// barras arredondadas, uma barra por dia (mesmo os sem gasto, com uma
// lasca fina). Cada barra com gasto é colorida com a cor da categoria
// que mais gastou naquele dia.
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GastosBarChart extends StatelessWidget {
  /// Um item por dia (todo dia do mês até hoje), já ordenado por data
  /// crescente. Dias sem gasto vêm com total 0.
  final List<({DateTime dia, double total, Color cor})> dados;

  const GastosBarChart({super.key, required this.dados});

  /// Arredonda o teto do eixo Y pra um número "bonito" (100, 200, 500,
  /// 1000...), igual ao gráfico "Resumo da semana".
  double _niceMax(double maxVal) {
    if (maxVal <= 0) return 10;
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

  String _formatEixoY(double valor) {
    if (valor >= 1000) return '${(valor / 1000).toStringAsFixed(1)}k';
    return valor.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    if (dados.isEmpty) return const SizedBox.shrink();

    final maiorValor = dados.map((d) => d.total).reduce((a, b) => a > b ? a : b);
    final chartMax = _niceMax(maiorValor);
    final gridInterval = chartMax / 4;

    // Com até 31 dias no mês, mostrar rótulo embaixo só a cada N dias.
    final passoRotulo = (dados.length / 6).ceil().clamp(1, 31);

    return SizedBox(
      height: 170,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: chartMax,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final item = dados[group.x];
                final d = item.dia;
                return BarTooltipItem(
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}\nR\$ ${item.total.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: gridInterval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: gridInterval,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    _formatEixoY(value),
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= dados.length || i % passoRotulo != 0) {
                    return const SizedBox.shrink();
                  }
                  final d = dados[i].dia;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < dados.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: dados[i].total > 0 ? dados[i].total : chartMax * 0.015,
                    color: dados[i].total > 0
                        ? dados[i].cor
                        : Colors.white.withValues(alpha: 0.12),
                    width: 8,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
