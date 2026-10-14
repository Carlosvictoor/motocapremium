// Primeira aba do app: onde o motoboy registra cada saída (entrega) do
// dia, vê os totais de hoje (saídas, ganho, KM, tempo online) e a lista
// das últimas saídas registradas.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'confirmar_entrega_page.dart';
import 'models.dart';
import 'utils.dart';
import 'auth_service.dart';

const _urlConfirmacaoIfood = 'https://confirmacao-entrega-propria.ifood.com.br/';
const _urlConfirmacao99Food = 'https://food-b-h5.99app.com/pt-BR/v2/confirmation-entrega';

class HomeTab extends StatefulWidget {
  final List<Saida> saidas;
  final double totalDia;
  final double kmHoje;
  final Duration tempoOnline;
  final String? statusOdometro;
  final DateTime? ultimaLeituraOdometro;
  final double? kmManualInicio;
  final Future<void> Function(double kmInicial) onIniciarKmManual;
  final Future<void> Function(double kmFinal) onFinalizarKmManual;
  final Future<void> Function({
    required String paga,
    required String comanda,
    required String taxa,
    required String gorjeta,
  }) onRegistrar;
  final VoidCallback onZerar;
  final VoidCallback onEnviarResumo;
  final VoidCallback onVerFinanceiro;
  final Future<void> Function(Saida) onDeletarSaida;
  final Future<void> Function(Saida, {required String comanda, required String taxa}) onEditarSaida;

  const HomeTab({
    super.key,
    required this.saidas,
    required this.totalDia,
    required this.kmHoje,
    required this.tempoOnline,
    this.statusOdometro,
    this.ultimaLeituraOdometro,
    this.kmManualInicio,
    required this.onIniciarKmManual,
    required this.onFinalizarKmManual,
    required this.onRegistrar,
    required this.onZerar,
    required this.onEnviarResumo,
    required this.onVerFinanceiro,
    required this.onDeletarSaida,
    required this.onEditarSaida,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final pagaController = TextEditingController();
  final comandaController = TextEditingController();
  final taxaController = TextEditingController();
  final gorjetaController = TextEditingController();

  @override
  void dispose() {
    pagaController.dispose();
    comandaController.dispose();
    taxaController.dispose();
    gorjetaController.dispose();
    super.dispose();
  }

  /// Pega o que foi digitado nos campos (Paga, Comanda, Taxa, Gorjeta),
  /// manda registrar a saída e limpa os campos pra próxima.
  Future<void> _registrar() async {
    await widget.onRegistrar(
      paga: pagaController.text.trim(),
      comanda: comandaController.text.trim(),
      taxa: taxaController.text.trim(),
      gorjeta: gorjetaController.text.trim(),
    );
    pagaController.clear();
    comandaController.clear();
    taxaController.clear();
    gorjetaController.clear();
  }

  @override
  Widget build(BuildContext context) {
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
                    Expanded(
                      child: Text(
                        'Bem Vindo,\n${AuthService.nomeLogado} 👋',
                        style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            height: 1.3),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    children: [
                      const Row(children: [
                        Icon(Icons.edit_note, color: Colors.blue, size: 30),
                        SizedBox(width: 10),
                        Text('Registrar saída',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 25),
                      _campo(
                          controller: pagaController,
                          titulo: 'Paga (R\$)',
                          icone: Icons.wallet,
                          cor: Colors.blue,
                          isNumeric: true),
                      _campo(
                          controller: comandaController,
                          titulo: 'Comandas',
                          hint: 'Ex: 12, 29, 30',
                          icone: Icons.receipt_long,
                          cor: Colors.purple),
                      _campo(
                          controller: taxaController,
                          titulo: 'Taxa (R\$)',
                          icone: Icons.attach_money,
                          cor: Colors.green,
                          isNumeric: true),
                      _campo(
                          controller: gorjetaController,
                          titulo: 'Gorjeta (R\$)',
                          icone: Icons.favorite,
                          cor: Colors.orange,
                          isNumeric: true),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: _registrar,
                          icon: const Icon(Icons.save),
                          label: const Text('Registrar saída',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                _botao(
                  titulo: 'Ver Financeiro',
                  cor: Colors.blue,
                  icone: Icons.bar_chart,
                  onTap: widget.onVerFinanceiro,
                ),
                const SizedBox(height: 15),
                _botao(
                    titulo: 'Enviar resumo',
                    cor: Colors.green,
                    icone: Icons.send,
                    onTap: widget.onEnviarResumo),
                const SizedBox(height: 15),
                _botao(
                    titulo: 'Zerar o dia',
                    cor: Colors.red,
                    icone: Icons.power_settings_new,
                    onTap: widget.onZerar),
                const SizedBox(height: 15),
                _botao(
                    titulo: 'Confirmar entrega 99/iFood',
                    cor: Colors.purple,
                    icone: Icons.local_shipping,
                    onTap: _escolherPlataformaConfirmacao),

                const SizedBox(height: 30),

                Row(
                  children: [
                    Expanded(
                        child: _resumoCard('Total de saídas',
                            contarSaidas(widget.saidas).toString(), Colors.blue)),
                    const SizedBox(width: 15),
                    Expanded(
                        child: _resumoCard('Total ganho',
                            'R\$ ${widget.totalDia.toStringAsFixed(2)}', Colors.green)),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                        child: _resumoCard('KM rodado hoje',
                            '${widget.kmHoje.toStringAsFixed(1)} km', Colors.purple,
                            trailing: _botaoKmManual())),
                    const SizedBox(width: 15),
                    Expanded(
                        child: _resumoCard('Tempo online',
                            _formatarDuracao(widget.tempoOnline), Colors.orange)),
                  ],
                ),
                _statusGps(),
                _statusKmManual(),

                const SizedBox(height: 25),

                const Text('Últimas saídas',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),

                if (widget.saidas.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Center(
                      child: Column(children: [
                        Icon(Icons.motorcycle, color: Colors.white24, size: 50),
                        SizedBox(height: 10),
                        Text('Nenhuma saída registrada',
                            style: TextStyle(color: Colors.white38, fontSize: 16)),
                      ]),
                    ),
                  )
                else
                  ...widget.saidas.map((s) => _saidaCard(s)),

                if (widget.saidas.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Saídas',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(
                                contarSaidas(widget.saidas).toString(),
                                style: const TextStyle(
                                    color: Colors.blue,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 45, color: Colors.white12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Total do dia',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(
                                'R\$ ${widget.totalDia.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pergunta de qual plataforma é a entrega (não dá pra saber sem
  /// perguntar — as duas usam o mesmo formato de código de 8 dígitos) e
  /// abre a confirmação correspondente.
  Future<void> _escolherPlataformaConfirmacao() async {
    final plataforma = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('De qual plataforma é essa entrega?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.delivery_dining, color: Colors.red),
              title: const Text('iFood'),
              onTap: () => Navigator.pop(ctx, 'ifood'),
            ),
            ListTile(
              leading: const Icon(Icons.delivery_dining, color: Colors.yellow),
              title: const Text('99Food'),
              onTap: () => Navigator.pop(ctx, '99food'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (plataforma == null || !mounted) return;

    final url = plataforma == 'ifood' ? _urlConfirmacaoIfood : _urlConfirmacao99Food;
    final titulo = plataforma == 'ifood' ? 'Confirmar entrega — iFood' : 'Confirmar entrega — 99Food';

    // Na Web, esses sites podem recusar ser exibidos dentro de outra página
    // (frame bloqueado) — mais seguro abrir numa aba nova. No app nativo
    // (Android/iOS/desktop), a WebView funciona normal porque não é
    // considerada "frame" pelo navegador.
    if (kIsWeb) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConfirmarEntregaPage(titulo: titulo, url: url)),
    );
  }

  /// Card de uma saída registrada, mostrando hora, valores (chips) e botão
  /// de excluir.
  Widget _saidaCard(Saida s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
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
              const Icon(Icons.motorcycle, color: Colors.blue, size: 22),
              const SizedBox(width: 8),
              const Text('Saída',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(s.horaStr,
                  style: const TextStyle(color: Colors.white38, fontSize: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => _dialogEditar(s),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit, color: Colors.blue, size: 18),
                ),
              ),
              GestureDetector(
                onTap: () => widget.onDeletarSaida(s),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete, color: Colors.red, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.paga != null) _chip('💳', 'R\$ ${s.paga}', Colors.blue),
              if (s.taxa != null) _chip('💰', 'R\$ ${s.taxa}', Colors.green),
              if (s.gorjeta != null) _chip('🎁', 'R\$ ${s.gorjeta}', Colors.orange),
              if (s.comandas != null) _chip('🧾', s.comandas!, Colors.purple),
            ],
          ),
          if (s.valorTotal > 0) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total da saída',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
                Text(
                  'R\$ ${s.valorTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Abre um dialog pra corrigir a comanda e/ou a taxa de uma saída já
  /// registrada (caso o motoboy erre ao digitar) — não mexe em Paga/Gorjeta.
  Future<void> _dialogEditar(Saida s) async {
    final comandaController = TextEditingController(text: s.comandas ?? '');
    final taxaController = TextEditingController(text: s.taxa ?? '');

    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Editar saída'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: comandaController,
              decoration: const InputDecoration(labelText: 'Comandas'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: taxaController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Taxa (R\$)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (salvou == true) {
      await widget.onEditarSaida(s, comanda: comandaController.text, taxa: taxaController.text);
    }
  }

  /// Etiqueta pequena e colorida usada pra mostrar cada valor (Paga, Taxa,
  /// Gorjeta, Comandas) dentro do card da saída.
  Widget _chip(String emoji, String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$emoji $texto',
        style: TextStyle(color: cor, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Campo de texto do formulário de registrar saída (Paga, Comanda, Taxa
  /// ou Gorjeta), com teclado numérico quando for um valor em dinheiro.
  Widget _campo({
    required TextEditingController controller,
    required String titulo,
    String? hint,
    required IconData icone,
    required Color cor,
    bool isNumeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            style: const TextStyle(fontSize: 20),
            keyboardType: isNumeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
              hintText: hint ?? '0,00',
              prefixIcon: Icon(icone, color: cor),
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  /// Botão grande de contorno colorido usado nas ações da Home (Ver
  /// Financeiro, Enviar resumo, Zerar o dia).
  Widget _botao({
    required String titulo,
    required Color cor,
    required IconData icone,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: onTap ?? () {},
        icon: Icon(icone, color: cor),
        label: Text(titulo,
            style: const TextStyle(color: Colors.white, fontSize: 20)),
      ),
    );
  }

  /// Card pequeno com um título e um valor em destaque, usado na grade de
  /// estatísticas (Total de saídas, Total ganho, KM rodado, Tempo online).
  /// [trailing] é um widget extra opcional ao lado do valor (usado pelo
  /// botão Iniciar/Finalizar do KM manual).
  Widget _resumoCard(String titulo, String valor, Color cor, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(valor,
                    style: TextStyle(
                        fontSize: 22, color: cor, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }

  /// Botãozinho ao lado do "KM rodado hoje": "Iniciar" (verde) quando não
  /// tem nenhuma contagem manual em andamento, ou "Finalizar" (laranja)
  /// quando já tem um KM inicial salvo esperando o KM final.
  Widget _botaoKmManual() {
    final emAndamento = widget.kmManualInicio != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: emAndamento ? Colors.orange : Colors.green),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: emAndamento ? _abrirDialogoFinalizarKm : _abrirDialogoIniciarKm,
        icon: Icon(emAndamento ? Icons.flag : Icons.play_arrow,
            color: emAndamento ? Colors.orange : Colors.green, size: 15),
        label: Text(emAndamento ? 'Finalizar' : 'Iniciar',
            style: TextStyle(
                color: emAndamento ? Colors.orange : Colors.green, fontSize: 12)),
      ),
    );
  }

  /// Linha pequena avisando que tem uma contagem manual de KM em
  /// andamento (aparece só depois de apertar "Iniciar").
  Widget _statusKmManual() {
    final inicio = widget.kmManualInicio;
    if (inicio == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        const Icon(Icons.route, color: Colors.orange, size: 14),
        const SizedBox(width: 6),
        Text('Contagem manual em andamento · iniciou em ${inicio.toStringAsFixed(1)} km',
            style: const TextStyle(color: Colors.orange, fontSize: 11)),
      ]),
    );
  }

  /// Diálogo "KM inicial": o motoboy digita o que está no odômetro da moto
  /// pra começar a contagem manual do KM rodado.
  Future<void> _abrirDialogoIniciarKm() async {
    final ctrl = TextEditingController();
    final kmInicial = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.route, color: Colors.purple),
          SizedBox(width: 10),
          Text('KM inicial'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Digite o KM inicial para começar a contagem.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('KM inicial', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1B2435),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final valor = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              if (valor == null) return;
              Navigator.pop(dialogCtx, valor);
            },
            child: const Text('Iniciar contagem', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (kmInicial != null) await widget.onIniciarKmManual(kmInicial);
  }

  /// Diálogo "Finalizar KM": o motoboy digita o KM final e vê na hora
  /// quantos km foram percorridos (final - inicial) antes de confirmar.
  Future<void> _abrirDialogoFinalizarKm() async {
    final kmInicial = widget.kmManualInicio;
    if (kmInicial == null) return;
    final ctrl = TextEditingController();
    double percorrido = 0;
    final kmFinal = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.flag, color: Colors.orange),
            SizedBox(width: 10),
            Text('Finalizar KM'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Digite o KM final para calcular a distância percorrida.',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),
              const Text('KM final', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1B2435),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (t) {
                  final valor = double.tryParse(t.trim().replaceAll(',', '.'));
                  setDialogState(() => percorrido = valor == null ? 0 : (valor - kmInicial));
                },
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2435),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('KM percorrido',
                        style: TextStyle(color: Colors.white54, fontSize: 14)),
                    Row(children: [
                      Text('${(percorrido < 0 ? 0 : percorrido).toStringAsFixed(1)} km',
                          style: const TextStyle(
                              color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      const Icon(Icons.motorcycle, color: Colors.white38, size: 20),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final valor = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
                if (valor == null) return;
                Navigator.pop(dialogCtx, valor);
              },
              child: const Text('Finalizar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (kmFinal != null) await widget.onFinalizarKmManual(kmFinal);
  }

  /// Formata a duração do "Tempo online" no padrão "01h 30min".
  String _formatarDuracao(Duration d) => formatarDuracaoMin(d.inMinutes);

  /// Linha pequena embaixo dos cards de KM/Tempo mostrando se o GPS está
  /// funcionando: erro (vermelho), esperando o primeiro sinal (cinza) ou
  /// ativo com a hora da última leitura (verde).
  Widget _statusGps() {
    if (widget.statusOdometro != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          const Icon(Icons.gps_off, color: Colors.red, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.statusOdometro!,
                style: const TextStyle(color: Colors.red, fontSize: 11)),
          ),
        ]),
      );
    }
    final ultima = widget.ultimaLeituraOdometro;
    final texto = ultima == null
        ? 'Aguardando sinal de GPS para contar o KM...'
        : 'GPS ativo · última leitura ${_haQuanto(ultima)}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Icon(ultima == null ? Icons.gps_not_fixed : Icons.gps_fixed,
            color: ultima == null ? Colors.white38 : Colors.green, size: 14),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  /// Texto relativo tipo "há 5s" / "há 3min" / "há 2h" a partir de um horário.
  String _haQuanto(DateTime momento) {
    final diff = DateTime.now().difference(momento);
    if (diff.inSeconds < 60) return 'há ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    return 'há ${diff.inHours}h';
  }
}
