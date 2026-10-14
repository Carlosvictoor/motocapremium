// Tela com o histórico de meses já fechados: resumo geral, e um card por
// mês com as métricas (ganho, gastos, lucro, saídas), gráfico semanal e
// o melhor dia daquele mês.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';
import 'utils.dart';

class MesesFechadosPage extends StatefulWidget {
  final List<MesFechado> meses;
  final Future<void> Function(MesFechado) onDeletarMes;

  const MesesFechadosPage({super.key, required this.meses, required this.onDeletarMes});

  @override
  State<MesesFechadosPage> createState() => _MesesFechadosPageState();
}

class _MesesFechadosPageState extends State<MesesFechadosPage> {
  late List<MesFechado> _meses;

  @override
  void initState() {
    super.initState();
    _meses = List.from(widget.meses);
  }

  /// Pergunta se quer mesmo excluir o mês fechado (apaga tudo daquele mês,
  /// sem volta) e, se confirmar, remove da lista.
  Future<void> _deletar(MesFechado mes) async {
    final label = labelMes(mes.mes, mes.ano);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: Colors.red),
          SizedBox(width: 10),
          Text('Excluir mês?'),
        ]),
        content: Text(
          'Excluir o fechamento de $label?\nTodos os dados do mês serão removidos.\nEssa ação não pode ser desfeita.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onDeletarMes(mes);
    setState(() => _meses.remove(mes));
  }

  /// Soma quantas saídas de verdade (com Taxa/Comanda) aconteceram no mês.
  int _totalSaidasMes(MesFechado mes) =>
      mes.dias.fold(0, (s, d) => s + d.totalSaidas);

  /// Agrupa o ganho do mês em 5 blocos de semana (dias 1-7, 8-14...) pra
  /// desenhar o gráfico de barras semanal.
  List<double> _semanal(MesFechado mes) {
    final totals = [0.0, 0.0, 0.0, 0.0, 0.0];
    for (final d in mes.dias) {
      totals[((d.data.day - 1) ~/ 7).clamp(0, 4)] += d.total;
    }
    return totals;
  }

  /// Acha o dia com maior ganho dentro do mês (ou null se o mês não tiver
  /// nenhum dia registrado).
  DiaRegistro? _melhorDia(MesFechado mes) {
    if (mes.dias.isEmpty) return null;
    return mes.dias.reduce((a, b) => a.total > b.total ? a : b);
  }

  /// Nome do dia da semana por extenso (ex: "Segunda-feira") a partir do
  /// número (1 a 7, igual ao `DateTime.weekday`).
  String _nomeDia(int weekday) {
    const n = ['Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo'];
    return n[(weekday - 1).clamp(0, 6)];
  }

  /// Calcula a variação percentual do ganho desse mês em relação ao mês
  /// anterior (null se não tiver mês anterior pra comparar).
  double? _comparacao(int index) {
    if (index >= _meses.length - 1) return null;
    final prev = _meses[index + 1].totalGanho;
    if (prev == 0) return null;
    return (_meses[index].totalGanho - prev) / prev * 100;
  }

  /// Nome do mês anterior ao mês do índice informado, usado no texto de
  /// comparação ("Comparado a Junho").
  String _nomeMesAnterior(int index) {
    if (index >= _meses.length - 1) return '';
    return nomesMeses[_meses[index + 1].mes];
  }

  @override
  Widget build(BuildContext context) {
    final totalGeralGanho  = _meses.fold(0.0, (s, m) => s + m.totalGanho);
    final totalGeralGastos = _meses.fold(0.0, (s, m) => s + m.totalGastos);
    final lucroGeral       = totalGeralGanho - totalGeralGastos;
    final totalSaidasGeral = _meses.fold(0, (s, m) => s + _totalSaidasMes(m));

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Text('Meses Fechados', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: [
                      Icon(Icons.tune, color: Colors.blue, size: 18),
                      SizedBox(width: 6),
                      Text('Filtrar', style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            if (_meses.isEmpty)
              Expanded(child: Center(
                child: Container(
                  margin: const EdgeInsets.all(18),
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
                  child: const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_month, color: Colors.white24, size: 60),
                    SizedBox(height: 15),
                    Text('Nenhum mês fechado ainda', style: TextStyle(color: Colors.white38, fontSize: 18)),
                    SizedBox(height: 8),
                    Text('Feche um mês no Financeiro\npara ver o histórico aqui.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white24, fontSize: 14)),
                  ]),
                ),
              ))
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      // Resumo geral — 4 métricas
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _topCard('Total Ganho',  'R\$ ${totalGeralGanho.toStringAsFixed(2)}',  Colors.green,  Icons.trending_up)),
                            Expanded(child: _topCard('Total Gastos', 'R\$ ${totalGeralGastos.toStringAsFixed(2)}', Colors.red,    Icons.trending_down)),
                            Expanded(child: _topCard('Lucro Total',  'R\$ ${lucroGeral.toStringAsFixed(2)}',        Colors.blue,   Icons.show_chart)),
                            Expanded(child: _topCard('Total de Saídas', totalSaidasGeral.toString(),                Colors.purple, Icons.local_shipping)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      ...List.generate(_meses.length, (i) => _mesCard(_meses[i], i)),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Um dos 4 mini-cards do resumo geral (ícone, título e valor).
  Widget _topCard(String titulo, String valor, Color cor, IconData icone) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icone, color: cor, size: 18),
        ),
        const SizedBox(height: 6),
        Text(titulo, style: const TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(valor, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  /// Card completo de um mês fechado: cabeçalho com nome do mês e
  /// comparação com o mês anterior, as 4 métricas, o gráfico semanal e o
  /// destaque do melhor dia.
  Widget _mesCard(MesFechado mes, int index) {
    final label    = labelMes(mes.mes, mes.ano);
    final total    = _totalSaidasMes(mes);
    final semanal  = _semanal(mes);
    final melhor   = _melhorDia(mes);
    final comp     = _comparacao(index);
    final mesAnt   = _nomeMesAnterior(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header do mês
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F35),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Mês fechado', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                if (comp != null) ...[
                  Text('Comparado a $mesAnt', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  const SizedBox(width: 3),
                  Icon(comp >= 0 ? Icons.trending_up : Icons.trending_down, color: comp >= 0 ? Colors.green : Colors.red, size: 13),
                  Text(' ${comp.abs().toStringAsFixed(0)}%', style: TextStyle(color: comp >= 0 ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _deletar(mes),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 4 métricas
                Row(children: [
                  Expanded(child: _metricBox('Total Ganho',     'R\$ ${mes.totalGanho.toStringAsFixed(2)}',  Colors.green,  Icons.wallet)),
                  const SizedBox(width: 6),
                  Expanded(child: _metricBox('Total Gastos',    'R\$ ${mes.totalGastos.toStringAsFixed(2)}', Colors.red,    Icons.trending_down)),
                  const SizedBox(width: 6),
                  Expanded(child: _metricBox('Lucro Líquido',   'R\$ ${mes.saldo.toStringAsFixed(2)}',       Colors.blue,   Icons.show_chart)),
                  const SizedBox(width: 6),
                  Expanded(child: _metricBox('Total de Saídas', total.toString(),                            Colors.purple, Icons.local_shipping)),
                ]),

                const SizedBox(height: 14),

                // Gráfico semanal + Melhor dia + Meta
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gráfico por semana
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Resumo semanal', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 130,
                            child: CustomPaint(
                              size: const Size(double.infinity, 130),
                              painter: _MonthBarPainter(values: semanal),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Melhor dia + Meta
                    SizedBox(
                      width: 120,
                      child: Column(
                        children: [
                          // Melhor dia
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF0D1117), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                    child: const Icon(Icons.emoji_events, color: Colors.orange, size: 13),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text('Melhor dia', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                ]),
                                const SizedBox(height: 6),
                                if (melhor != null) ...[
                                  Text(_nomeDia(melhor.data.weekday), style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                  Text('R\$ ${melhor.total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                                ] else
                                  const Text('—', style: TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ),

                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Uma das 4 caixinhas de métrica dentro do card do mês (Total Ganho,
  /// Total Gastos, Lucro Líquido, Total de Saídas).
  Widget _metricBox(String titulo, String valor, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 15),
          const SizedBox(height: 4),
          Text(titulo, style: const TextStyle(color: Colors.white54, fontSize: 9), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(valor, style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Gráfico de barras por semana (Sem 1 a Sem 5) desenhado à mão, mostrado
/// dentro do card de cada mês fechado.
class _MonthBarPainter extends CustomPainter {
  final List<double> values;

  const _MonthBarPainter({required this.values});

  /// Desenha as linhas de grade com os valores e uma barra por semana do mês.
  @override
  void paint(Canvas canvas, Size size) {
    const labels   = ['Sem 1', 'Sem 2', 'Sem 3', 'Sem 4', 'Sem 5'];
    const leftPad  = 36.0;
    const botPad   = 22.0;
    const topPad   = 6.0;

    final chartW = size.width - leftPad;
    final chartH = size.height - botPad - topPad;
    final maxVal = values.fold(0.0, math.max);
    final cMax   = maxVal <= 0 ? 800.0 : _niceMax(maxVal);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;

    final barPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH - (chartH * i / 4);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);

      tp.text = TextSpan(text: (cMax / 4 * i).round().toString(), style: const TextStyle(color: Color(0x40FFFFFF), fontSize: 9));
      tp.layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 3, y - tp.height / 2));
    }

    final barW = (chartW / 5) * 0.5;
    for (int i = 0; i < 5; i++) {
      final barH = cMax > 0 ? (values[i] / cMax * chartH).clamp(0.0, chartH) : 0.0;
      final x    = leftPad + (chartW / 5) * i + (chartW / 5) * 0.25;
      final y    = topPad + chartH - barH;

      if (barH > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, y, barW, barH), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          barPaint,
        );
      }

      tp.text = TextSpan(text: labels[i], style: const TextStyle(color: Color(0x50FFFFFF), fontSize: 9));
      tp.layout();
      tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, topPad + chartH + 5));
    }
  }

  /// Arredonda o valor máximo do eixo Y pra um número "bonito", igual ao
  /// gráfico da aba Financeiro.
  double _niceMax(double val) {
    final step = ((val / 4) / 100).ceil() * 100.0;
    return (step * 4 * 1.1).clamp(400.0, double.infinity);
  }

  /// Só redesenha se os valores semanais mudarem.
  @override
  bool shouldRepaint(_MonthBarPainter old) => old.values != values;
}
