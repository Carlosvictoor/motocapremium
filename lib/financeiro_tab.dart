// Aba Financeiro: resumo de ganhos/gastos do dia e da semana, formulário
// pra lançar gastos, histórico de dias (com filtro por mês) e acesso ao
// fechamento do mês.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'utils.dart';
import 'weekly_bar_chart.dart';
import 'gastos_bar_chart.dart';
import 'meses_fechados_page.dart';

class FinanceiroTab extends StatefulWidget {
  final List<DiaRegistro> dias;
  final List<Gasto> gastos;
  final List<MesFechado> mesesFechados;
  final double saidaTotal;
  final Future<void> Function(Gasto) onAdicionarGasto;
  final Future<void> Function(Gasto) onDeletarGasto;
  final VoidCallback onFecharMes;
  final Future<void> Function(DiaRegistro) onDeletarDia;
  final Future<void> Function(MesFechado) onDeletarMes;

  const FinanceiroTab({
    super.key,
    required this.dias,
    required this.gastos,
    required this.mesesFechados,
    required this.saidaTotal,
    required this.onAdicionarGasto,
    required this.onDeletarGasto,
    required this.onFecharMes,
    required this.onDeletarDia,
    required this.onDeletarMes,
  });

  @override
  State<FinanceiroTab> createState() => _FinanceiroTabState();
}

class _FinanceiroTabState extends State<FinanceiroTab> {
  final descricaoController = TextEditingController();
  final valorController = TextEditingController();
  String categoriaSelecionada = 'Combustível';
  String? _mesFiltro;
  bool _mostrarUltimosGastos = false;

  final List<Map<String, dynamic>> _categorias = [
    {'nome': 'Combustível', 'cor': Colors.orange, 'icone': Icons.local_gas_station},
    {'nome': 'Alimentação', 'cor': Colors.green, 'icone': Icons.restaurant},
    {'nome': 'Manutenção', 'cor': Colors.red, 'icone': Icons.build},
    {'nome': 'Outros', 'cor': Colors.grey, 'icone': Icons.more_horiz},
  ];

  @override
  void dispose() {
    descricaoController.dispose();
    valorController.dispose();
    super.dispose();
  }

  /// Quanto já foi ganho hoje: soma o que já está salvo no histórico de
  /// hoje (se houver) com as saídas ainda ativas (não zeradas).
  double get _ganhoHoje {
    final now = DateTime.now();
    final diasHoje = widget.dias
        .where((d) =>
            d.data.day == now.day &&
            d.data.month == now.month &&
            d.data.year == now.year)
        .fold(0.0, (s, d) => s + d.total);
    return widget.saidaTotal + diasHoje;
  }

  /// Soma dos gastos lançados hoje.
  double get _gastosHoje {
    final now = DateTime.now();
    return widget.gastos
        .where((g) =>
            g.data.day == now.day &&
            g.data.month == now.month &&
            g.data.year == now.year)
        .fold(0.0, (s, g) => s + g.valor);
  }

  /// Ganho de hoje menos gastos de hoje.
  double get _saldoHoje => _ganhoHoje - _gastosHoje;

  /// Monta o ganho de cada dia da semana atual (Segunda a Domingo), usado
  /// pelo gráfico de barras.
  Map<int, double> _ganhosSemana() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final result = <int, double>{};
    for (int i = 1; i <= 7; i++) {
      final day = monday.add(Duration(days: i - 1));
      final total = widget.dias
          .where((d) =>
              d.data.day == day.day &&
              d.data.month == day.month &&
              d.data.year == day.year)
          .fold(0.0, (s, d) => s + d.total);
      final isToday = day.day == now.day &&
          day.month == now.month &&
          day.year == now.year;
      result[i] = total + (isToday ? widget.saidaTotal : 0);
    }
    return result;
  }

  /// Soma o ganho da semana inteira (todos os dias de Segunda a Domingo).
  double get _ganhoSemana =>
      _ganhosSemana().values.fold(0, (a, b) => a + b);

  /// Soma dos gastos lançados durante a semana atual.
  double get _gastosSemana {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    return widget.gastos
        .where((g) =>
            !g.data.isBefore(
                DateTime(monday.year, monday.month, monday.day)) &&
            !g.data.isAfter(DateTime(
                sunday.year, sunday.month, sunday.day, 23, 59)))
        .fold(0.0, (s, g) => s + g.valor);
  }

  /// Ganho da semana menos gastos da semana.
  double get _saldoSemana => _ganhoSemana - _gastosSemana;

  /// Lista os meses (no formato "mês/ano") que têm algum dia registrado,
  /// na ordem em que apareceram, pra montar os filtros do histórico.
  List<String> get _mesesDisponiveis {
    final seen = <String>{};
    final lista = <String>[];
    for (final d in widget.dias) {
      final chave = '${d.data.month}/${d.data.year}';
      if (seen.add(chave)) lista.add(chave);
    }
    return lista;
  }

  /// Transforma a chave "mês/ano" (ex: "7/2026") no nome por extenso
  /// (ex: "Julho 2026") pra mostrar no filtro.
  String _nomeDaChave(String chave) {
    final p = chave.split('/');
    return labelMes(int.parse(p[0]), int.parse(p[1]));
  }

  /// Lista de dias filtrada pelo mês selecionado (ou todos, se nenhum
  /// filtro estiver marcado).
  List<DiaRegistro> get _diasFiltrados {
    if (_mesFiltro == null) return widget.dias;
    return widget.dias
        .where((d) => '${d.data.month}/${d.data.year}' == _mesFiltro)
        .toList();
  }

  static const _nomesMeses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  /// Mês/ano de hoje, tipo "Setembro/2025" — o resumo é sempre do período
  /// atual em aberto (ainda não fechado).
  String get _mesAtualLabel {
    final agora = DateTime.now();
    return '${_nomesMeses[agora.month - 1]}/${agora.year}';
  }

  double get _totalGastosAtual =>
      widget.gastos.fold(0.0, (soma, g) => soma + g.valor);

  /// Total do mês fechado mais recente, pra comparar com o atual — 0 se
  /// nunca fechou nenhum mês ainda.
  double get _totalMesAnterior {
    if (widget.mesesFechados.isEmpty) return 0;
    final maisRecente = widget.mesesFechados.reduce(
      (a, b) => (a.ano > b.ano || (a.ano == b.ano && a.mes >= b.mes)) ? a : b,
    );
    return maisRecente.gastos.fold(0.0, (soma, g) => soma + g.valor);
  }

  /// Variação percentual do total atual em relação ao mês anterior fechado
  /// — null quando não dá pra comparar (nunca fechou um mês, ou o anterior
  /// não teve gasto nenhum).
  double? get _variacaoPercentual {
    final anterior = _totalMesAnterior;
    if (anterior <= 0) return null;
    return ((_totalGastosAtual - anterior) / anterior) * 100;
  }

  /// Total e quantidade de gastos por categoria, no período atual —
  /// sempre nas 4 categorias fixas, mesmo com total zero.
  List<({String nome, Color cor, IconData icone, double total, int quantidade})>
      get _resumoPorCategoria {
    return _categorias.map((cat) {
      final nome = cat['nome'] as String;
      final doCategoria = widget.gastos.where((g) => g.categoria == nome);
      return (
        nome: nome,
        cor: cat['cor'] as Color,
        icone: cat['icone'] as IconData,
        total: doCategoria.fold(0.0, (soma, g) => soma + g.valor),
        quantidade: doCategoria.length,
      );
    }).toList();
  }

  /// Gastos do período atual agrupados por dia (pro gráfico), sempre com
  /// UM item por dia do dia 1 do mês atual até hoje — inclusive dias sem
  /// nenhum gasto (total 0, cor neutra) — pra o gráfico ficar com várias
  /// barras e contexto, igual o "Resumo da semana". Cada barra com gasto
  /// usa a cor da categoria que mais gastou naquele dia.
  List<({DateTime dia, double total, Color cor})> get _dadosGraficoGastos {
    final porDia = <DateTime, List<Gasto>>{};
    for (final g in widget.gastos) {
      final chave = DateTime(g.data.year, g.data.month, g.data.day);
      porDia.putIfAbsent(chave, () => []).add(g);
    }

    final hoje = DateTime.now();
    final inicioMes = DateTime(hoje.year, hoje.month, 1);
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);

    return [
      for (var dia = inicioMes;
          !dia.isAfter(hojeSemHora);
          dia = dia.add(const Duration(days: 1)))
        () {
          final doDia = porDia[dia];
          if (doDia == null || doDia.isEmpty) {
            return (dia: dia, total: 0.0, cor: Colors.white.withValues(alpha: 0.14));
          }

          final total = doDia.fold(0.0, (soma, g) => soma + g.valor);
          final porCategoriaNoDia = <String, double>{};
          for (final g in doDia) {
            porCategoriaNoDia[g.categoria] = (porCategoriaNoDia[g.categoria] ?? 0) + g.valor;
          }
          final categoriaDominante =
              porCategoriaNoDia.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
          final cor = doDia.firstWhere((g) => g.categoria == categoriaDominante).cor;

          return (dia: dia, total: total, cor: cor);
        }(),
    ];
  }

  /// Lê a descrição e o valor digitados, monta um Gasto novo com a
  /// categoria selecionada e manda salvar.
  Future<void> _adicionarGasto() async {
    final descricao = descricaoController.text.trim();
    final valorText = valorController.text.trim();
    if (descricao.isEmpty || valorText.isEmpty) return;

    final valor = double.tryParse(valorText.replaceAll(',', '.')) ?? 0;
    if (valor <= 0) return;

    final cat = _categorias.firstWhere((c) => c['nome'] == categoriaSelecionada);

    final gasto = Gasto(
      descricao: descricao,
      valor: valor,
      data: DateTime.now(),
      cor: cat['cor'] as Color,
      icone: cat['icone'] as IconData,
      categoria: categoriaSelecionada,
    );

    await widget.onAdicionarGasto(gasto);

    descricaoController.clear();
    valorController.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gasto adicionado!'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final saldo = _saldoHoje;
    final saldoCor = saldo >= 0 ? Colors.blue : Colors.red;
    final weeklyData = _ganhosSemana();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header
                const Text('Financeiro',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold)),

                const SizedBox(height: 20),

                // 2. Three summary cards
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.trending_up,
                        iconColor: Colors.green,
                        label: 'Total Ganho',
                        value: 'R\$ ${_ganhoHoje.toStringAsFixed(2)}',
                        valueColor: Colors.green,
                        sublabel: 'Hoje',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.trending_down,
                        iconColor: Colors.red,
                        label: 'Total Gastos',
                        value: 'R\$ ${_gastosHoje.toStringAsFixed(2)}',
                        valueColor: Colors.red,
                        sublabel: 'Hoje',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _summaryCard(
                        icon: saldo >= 0
                            ? Icons.account_balance_wallet
                            : Icons.warning_amber,
                        iconColor: saldoCor,
                        label: 'Saldo Líquido',
                        value: 'R\$ ${saldo.toStringAsFixed(2)}',
                        valueColor: saldoCor,
                        sublabel: 'Hoje',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 3. Weekly summary card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          const Text('Resumo da semana',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B2435),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Essa semana',
                                    style: TextStyle(
                                        color: Colors.white60, fontSize: 12)),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down,
                                    color: Colors.white.withValues(alpha: 0.38),
                                    size: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Ganho',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                Text(
                                  'R\$ ${_ganhoSemana.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Gastos',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                Text(
                                  'R\$ ${_gastosSemana.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Saldo',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                Text(
                                  'R\$ ${_saldoSemana.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: _saldoSemana >= 0
                                          ? Colors.blue
                                          : Colors.red,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      WeeklyBarChart(earnings: weeklyData),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4. Gasto form
                const Text('Adicionar gasto',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categorias.map((cat) {
                      final selected = cat['nome'] == categoriaSelecionada;
                      final cor = cat['cor'] as Color;
                      return GestureDetector(
                        onTap: () => setState(
                            () => categoriaSelecionada = cat['nome'] as String),
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? cor : const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                                color: selected
                                    ? Colors.transparent
                                    : Colors.white24),
                          ),
                          child: Row(
                            children: [
                              Icon(cat['icone'] as IconData,
                                  color: selected ? Colors.white : cor,
                                  size: 18),
                              const SizedBox(width: 6),
                              Text(
                                cat['nome'] as String,
                                style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Descrição',
                          style: TextStyle(
                              fontSize: 15, color: Colors.white70)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descricaoController,
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Ex: Gasolina, almoço...',
                          filled: true,
                          fillColor: const Color(0xFF1B2435),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Valor (R\$)',
                          style: TextStyle(
                              fontSize: 15, color: Colors.white70)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: valorController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          prefixText: 'R\$  ',
                          prefixStyle: const TextStyle(
                              color: Colors.white54, fontSize: 16),
                          hintText: '0,00',
                          filled: true,
                          fillColor: const Color(0xFF1B2435),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: _adicionarGasto,
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar gasto',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4.1 Resumo do mês (cards por categoria + gráfico)
                _resumoDoMes(),

                const SizedBox(height: 24),

                // 5. Gastos list — só aparece depois de tocar num card do
                // resumo acima.
                if (_mostrarUltimosGastos && widget.gastos.isNotEmpty) ...[
                  const Text('Últimos gastos',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...widget.gastos.map((g) => _gastoCard(g)),
                ],

                const SizedBox(height: 20),

                // 6. Fechar Mês / Meses Fechados
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 55,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.purple),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: widget.onFecharMes,
                          icon: const Icon(Icons.calendar_month,
                              color: Colors.purple),
                          label: const Text('Fechar Mês',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 55,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B1040),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: const BorderSide(
                                  color: Colors.purpleAccent),
                            ),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MesesFechadosPage(
                                meses: widget.mesesFechados,
                                onDeletarMes: widget.onDeletarMes,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.history,
                              color: Colors.purpleAccent),
                          label: const Text('Meses Fechados',
                              style: TextStyle(
                                  color: Colors.purpleAccent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 7. Histórico de dias with month filter
                const Text('Histórico de dias',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                if (_mesesDisponiveis.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chipFiltro('Todos', _mesFiltro == null,
                            () => setState(() => _mesFiltro = null)),
                        ..._mesesDisponiveis.map((chave) => _chipFiltro(
                              _nomeDaChave(chave),
                              _mesFiltro == chave,
                              () => setState(() =>
                                  _mesFiltro = _mesFiltro == chave ? null : chave),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (_diasFiltrados.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Center(
                      child: Column(children: [
                        Icon(Icons.inbox, color: Colors.white24, size: 50),
                        SizedBox(height: 10),
                        Text('Nenhum dia registrado ainda',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 16)),
                        SizedBox(height: 5),
                        Text("Clique em 'Zerar o dia' na aba Home",
                            style: TextStyle(
                                color: Colors.white24, fontSize: 13)),
                      ]),
                    ),
                  )
                else
                  ..._diasFiltrados.map((d) => _diaCard(d)),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Um dos três cards pequenos do topo (Total Ganho, Total Gastos, Saldo).
  Widget _summaryCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
    required String sublabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          Text(sublabel,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  /// Resumo do mês atual: cards por categoria + gráfico de gastos por dia.
  /// Tocar em qualquer card revela a lista "Últimos gastos" logo abaixo
  /// (começa escondida).
  Widget _resumoDoMes() {
    final variacao = _variacaoPercentual;
    final subiu = (variacao ?? 0) >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.blue, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resumo do mês',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Seus gastos em um só lugar',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2435),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.white54, size: 14),
                    const SizedBox(width: 6),
                    Text(_mesAtualLabel, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: _resumoPorCategoria.map((c) {
              return GestureDetector(
                onTap: () => setState(() => _mostrarUltimosGastos = true),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.cor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(c.icone, color: c.cor, size: 18),
                      const Spacer(),
                      Text(c.nome,
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                          overflow: TextOverflow.ellipsis),
                      Text('R\$ ${c.total.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.cor)),
                      Text('${c.quantidade} ${c.quantidade == 1 ? 'gasto' : 'gastos'}',
                          style: const TextStyle(fontSize: 10, color: Colors.white38)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          if (_dadosGraficoGastos.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.show_chart, color: Colors.white54, size: 16),
                const SizedBox(width: 6),
                const Text('Total de gastos',
                    style: TextStyle(fontSize: 13, color: Colors.white70)),
                const Spacer(),
                if (variacao != null)
                  Row(
                    children: [
                      Icon(subiu ? Icons.arrow_upward : Icons.arrow_downward,
                          color: subiu ? Colors.red : Colors.green, size: 14),
                      Text('${variacao.abs().toStringAsFixed(0)}%',
                          style: TextStyle(
                              color: subiu ? Colors.red : Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
              ],
            ),
            Text('R\$ ${_totalGastosAtual.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (variacao != null)
              const Text('em relação ao mês anterior',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 8),
            GastosBarChart(dados: _dadosGraficoGastos),
          ],
        ],
      ),
    );
  }

  /// Card de um gasto na lista "Últimos gastos", com botão de excluir.
  Widget _gastoCard(Gasto gasto) {
    final d = gasto.data;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: gasto.cor.withValues(alpha: 0.2),
            child: Icon(gasto.icone, color: gasto.cor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gasto.categoria,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                Text(gasto.descricao,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('R\$ ${gasto.valor.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.red,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              Text(dateStr,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(width: 6),
          // Delete
          GestureDetector(
            onTap: () => widget.onDeletarGasto(gasto),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete, color: Colors.red, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// Monta o resumo de um dia em texto e abre o WhatsApp pra compartilhar
  /// (usado no botão de compartilhar do card do dia, no histórico).
  Future<void> _compartilharDia(DiaRegistro dia) async {
    final dataStr =
        '${dia.data.day.toString().padLeft(2, '0')}/${dia.data.month.toString().padLeft(2, '0')}/${dia.data.year}';

    final msg = StringBuffer();
    msg.writeln('🏍️ *Motoca Premium — Resumo do Dia*');
    msg.writeln('📅 $dataStr');
    msg.writeln('━━━━━━━━━━━━━━━━━━━━');
    msg.writeln('');

    final lista = dia.saidas.reversed.toList();
    for (int i = 0; i < lista.length; i++) {
      final s = lista[i];
      msg.writeln('*Saída ${i + 1}* (${s.horaStr})');
      if (s.paga != null) msg.writeln('  💳 Paga: R\$ ${s.paga}');
      if (s.taxa != null) msg.writeln('  💰 Taxa: R\$ ${s.taxa}');
      if (s.gorjeta != null) msg.writeln('  🎁 Gorjeta: R\$ ${s.gorjeta}');
      if (s.comandas != null) msg.writeln('  🧾 Comandas: ${s.comandas}');
      if (s.valorTotal > 0) msg.writeln('  💵 _Total: R\$ ${s.valorTotal.toStringAsFixed(2)}_');
      if (i < lista.length - 1) msg.writeln('');
    }

    msg.writeln('');
    msg.writeln('━━━━━━━━━━━━━━━━━━━━');
    msg.writeln('🚗 *Total de saídas:* ${dia.totalSaidas}');
    msg.writeln('💵 *Total ganho:* R\$ ${dia.total.toStringAsFixed(2)}');
    msg.writeln('━━━━━━━━━━━━━━━━━━━━');
    msg.writeln('_Enviado via Motoca Premium_ 🚀');

    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg.toString())}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Card de um dia no histórico: data, quantidade de saídas, KM/tempo
  /// online (se tiver), total ganho e os botões de compartilhar/excluir.
  Widget _diaCard(DiaRegistro dia) {
    final dataStr =
        '${dia.data.day.toString().padLeft(2, '0')}/${dia.data.month.toString().padLeft(2, '0')}/${dia.data.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          // Data e saídas
          Expanded(
            child: Row(children: [
              const Icon(Icons.calendar_today, color: Colors.blue, size: 18),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dataStr,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    '${dia.totalSaidas} saída${dia.totalSaidas != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  if (dia.kmRodado > 0 || dia.tempoOnlineMin > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '🛣️ ${dia.kmRodado.toStringAsFixed(1)} km  •  ⏱ ${formatarDuracaoMin(dia.tempoOnlineMin)}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ]),
          ),
          // Total
          Text('R\$ ${dia.total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 16,
                  color: Colors.green,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          // Compartilhar
          GestureDetector(
            onTap: () => _compartilharDia(dia),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.share, color: Colors.green, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          // Excluir
          GestureDetector(
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF111827),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Row(children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Excluir dia?'),
                  ]),
                  content: Text(
                    'Excluir o registro de $dataStr?\nEssa ação não pode ser desfeita.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Excluir',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (ok == true) widget.onDeletarDia(dia);
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// Botão de filtro (chip) usado na lista de meses do histórico de dias.
  Widget _chipFiltro(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: selected ? Colors.transparent : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}
