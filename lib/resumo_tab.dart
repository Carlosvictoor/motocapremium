// Aba Resumo: mostra as estatísticas de hoje (ou de um dia escolhido no
// calendário) e o histórico geral do mês em aberto (dias trabalhados,
// total ganho, KM, tempo online).
import 'package:flutter/material.dart';
import 'models.dart';
import 'utils.dart';
import 'atividades_page.dart';

class ResumoTab extends StatefulWidget {
  final List<DiaRegistro> dias;
  final List<Saida> saidas;
  final double totalDia;
  final List<Gasto> gastos;
  final double kmTotal;
  final Duration tempoOnline;

  const ResumoTab({
    super.key,
    required this.dias,
    required this.saidas,
    required this.totalDia,
    required this.gastos,
    required this.kmTotal,
    required this.tempoOnline,
  });

  @override
  State<ResumoTab> createState() => _ResumoTabState();
}

class _ResumoTabState extends State<ResumoTab> {
  DateTime? _diaEscolhido;
  bool _atividadesExpandido = true;

  /// Verifica se a data informada é o dia de hoje.
  bool _ehHoje(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// Verifica se duas datas caem no mesmo dia (ignorando a hora).
  bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Abre o calendário pra escolher um dia específico do histórico. Se
  /// escolher hoje, volta a mostrar os dados "ao vivo" em vez do histórico
  /// salvo.
  Future<void> _escolherDia() async {
    final now = DateTime.now();
    final escolhido = await showDatePicker(
      context: context,
      initialDate: _diaEscolhido ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.blue),
        ),
        child: child!,
      ),
    );
    if (escolhido != null) {
      setState(() => _diaEscolhido = _ehHoje(escolhido) ? null : escolhido);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mostrandoHoje = _diaEscolhido == null;

    int saidasCount;
    double totalDoDia;
    double kmDoDia;
    int tempoOnlineDoDiaMin;
    String labelDia;

    if (mostrandoHoje) {
      saidasCount = contarSaidas(widget.saidas);
      totalDoDia = widget.totalDia;
      kmDoDia = widget.kmTotal;
      tempoOnlineDoDiaMin = widget.tempoOnline.inMinutes;
      labelDia = 'Hoje';
    } else {
      final diasFiltro = widget.dias
          .where((d) => _mesmoDia(d.data, _diaEscolhido!))
          .toList();
      saidasCount = diasFiltro.fold(0, (s, d) => s + d.totalSaidas);
      totalDoDia = diasFiltro.fold(0.0, (s, d) => s + d.total);
      kmDoDia = diasFiltro.fold(0.0, (s, d) => s + d.kmRodado);
      tempoOnlineDoDiaMin = diasFiltro.fold(0, (s, d) => s + d.tempoOnlineMin);
      labelDia = _formatarData(_diaEscolhido!);
    }

    final totalHistorico = widget.dias.fold(0.0, (s, d) => s + d.total);
    final totalSaidasHistorico =
        widget.dias.fold(0, (s, d) => s + d.totalSaidas);
    final totalGastosHistorico =
        widget.gastos.fold(0.0, (s, g) => s + g.valor);
    // Soma o histórico já fechado (dias) com o dia de hoje ainda em aberto.
    final kmTotal =
        widget.dias.fold(0.0, (s, d) => s + d.kmRodado) + widget.kmTotal;
    final tempoOnlineTotalMin =
        widget.dias.fold(0, (s, d) => s + d.tempoOnlineMin) + widget.tempoOnline.inMinutes;

    final ultimasAtividades = widget.dias.take(3).toList();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Resumo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Acompanhe seu desempenho diário.',
                              style: TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: _escolherDia,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.calendar_month, color: Colors.blue, size: 16),
                          const SizedBox(width: 8),
                          Text(mostrandoHoje ? _formatarData(DateTime.now()) : labelDia,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 16),
                        ]),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Row(children: [
                  Icon(mostrandoHoje ? Icons.today : Icons.calendar_month,
                      color: mostrandoHoje ? Colors.blue : Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(labelDia, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (!mostrandoHoje) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _diaEscolhido = null),
                      child: const Icon(Icons.close, color: Colors.white38, size: 16),
                    ),
                  ],
                ]),
                const SizedBox(height: 12),

                Row(children: [
                  Expanded(child: _statCardHoje(Icons.show_chart, 'Saídas', saidasCount.toString(), Colors.blue)),
                  const SizedBox(width: 10),
                  Expanded(child: _statCardHoje(Icons.account_balance_wallet_outlined, 'Total',
                      'R\$ ${totalDoDia.toStringAsFixed(2)}', Colors.green)),
                  const SizedBox(width: 10),
                  Expanded(child: _statCardHoje(Icons.location_on_outlined, 'KM rodado',
                      '${kmDoDia.toStringAsFixed(1)} km', Colors.purple)),
                  const SizedBox(width: 10),
                  Expanded(child: _statCardHoje(Icons.access_time, 'Tempo online',
                      formatarDuracaoMin(tempoOnlineDoDiaMin), Colors.orange)),
                ]),

                const SizedBox(height: 28),

                Row(children: [
                  const Icon(Icons.history, color: Colors.purple, size: 20),
                  const SizedBox(width: 8),
                  const Text('Histórico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 14),

                Row(children: [
                  Expanded(
                    child: _statCardHistoricoPequeno(
                        Icons.work_outline, 'Dias trabalhados', widget.dias.length.toString(), Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statCardHistoricoPequeno(
                        Icons.send_outlined, 'Total saídas', totalSaidasHistorico.toString(), Colors.blue),
                  ),
                ]),
                const SizedBox(height: 12),

                _statCardHistoricoGrande(Icons.attach_money, Icons.payments_outlined, 'Total ganho histórico',
                    'R\$ ${totalHistorico.toStringAsFixed(2)}', Colors.green),
                const SizedBox(height: 10),
                _statCardHistoricoGrande(Icons.remove_circle_outline, Icons.credit_card, 'Total gastos histórico',
                    'R\$ ${totalGastosHistorico.toStringAsFixed(2)}', Colors.red),
                const SizedBox(height: 10),
                _statCardHistoricoGrande(Icons.social_distance_outlined, Icons.map_outlined, 'Total KM rodado',
                    '${kmTotal.toStringAsFixed(1)} km', Colors.purple),
                const SizedBox(height: 10),
                _statCardHistoricoGrande(Icons.timer_outlined, Icons.hourglass_bottom, 'Total tempo online',
                    formatarDuracaoMin(tempoOnlineTotalMin), Colors.orange),

                const SizedBox(height: 28),

                if (widget.dias.isNotEmpty) ...[
                  InkWell(
                    onTap: () => setState(() => _atividadesExpandido = !_atividadesExpandido),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Últimas atividades', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      Icon(_atividadesExpandido ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.white38),
                    ]),
                  ),
                  if (_atividadesExpandido) ...[
                    const SizedBox(height: 12),
                    ...ultimasAtividades.map((d) => _diaRow(d)),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AtividadesPage(dias: widget.dias)),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Ver todas as atividades', style: TextStyle(color: Colors.blue, fontSize: 14)),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: Colors.blue, size: 16),
                        ]),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Card da seção "Hoje": badge circular com ícone em cima, rótulo e valor
  /// embaixo, tudo centralizado.
  Widget _statCardHoje(IconData icon, String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: cor.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: cor, size: 17),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(valor,
              style: TextStyle(color: cor, fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  /// Card pequeno da seção "Histórico" ("Dias trabalhados" / "Total saídas").
  Widget _statCardHistoricoPequeno(IconData icon, String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: cor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Text(valor, style: TextStyle(color: cor, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ]),
    );
  }

  /// Card cheio de largura da seção "Histórico" (ganho/gastos/km/tempo),
  /// com um ícone decorativo grande e apagado ao fundo.
  Widget _statCardHistoricoGrande(IconData iconFundo, IconData iconBadge, String label, String valor, Color cor) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor.withValues(alpha: 0.16), cor.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -14,
            child: Icon(iconFundo, size: 76, color: cor.withValues(alpha: 0.08)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: cor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(iconBadge, color: cor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(valor, style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Linha de um dia na lista "Últimas atividades" (data, KM/tempo se tiver,
  /// quantidade de saídas e total ganho naquele dia).
  Widget _diaRow(DiaRegistro dia) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.blue, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatarData(dia.data), style: const TextStyle(fontSize: 15)),
                if (dia.kmRodado > 0 || dia.tempoOnlineMin > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '🛣️ ${dia.kmRodado.toStringAsFixed(1)} km  •  ⏱ ${formatarDuracaoMin(dia.tempoOnlineMin)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          Text('${dia.totalSaidas} saída${dia.totalSaidas != 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(width: 12),
          Text('R\$ ${dia.total.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.green,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
        ],
      ),
    );
  }
}
