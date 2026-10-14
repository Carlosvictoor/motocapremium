// Tela que abre quando um login de restaurante entra no app (ver
// login_page.dart/app_shell.dart) — o restaurante configura a taxa de
// entrega por bairro e vincula motoboys que já usam o Motoca Premium.
// Só configuração por enquanto, sem lançar pedido (ver Fase 11 do plano).
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../chat/chat_service.dart';
import '../database.dart';
import '../localizacao_api.dart';
import '../widgets/selecionar_motoboy.dart';
import 'dialog_bairros_cidade.dart';
import 'relatorio_pdf.dart';
import 'restaurante_financeiro_api.dart';
import 'restaurante_lojas_api.dart';
import 'restaurante_relatorio_api.dart';
import 'restaurante_service.dart';

class RestauranteDashboard extends StatefulWidget {
  final VoidCallback onLogout;
  const RestauranteDashboard({super.key, required this.onLogout});

  @override
  State<RestauranteDashboard> createState() => _RestauranteDashboardState();
}

class _RestauranteDashboardState extends State<RestauranteDashboard> {
  int _navIndex = 0;
  bool _carregando = true;
  String _nomeConta = '';
  List<Bairro> _bairros = [];
  List<MotoboyVinculado> _vinculados = [];
  List<Map<String, dynamic>> _todosMotoboys = [];
  String? _motoboySelecionadoUid;
  TextEditingController? _motoboyFieldController;
  bool _vinculando = false;
  bool _usarTaxaMotocaPremium = false;

  List<Map<String, dynamic>> _lojas = [];
  final _nomeLojaController = TextEditingController();
  final _merchantIdController = TextEditingController();
  String? _motoboyLojaSelecionadoUid;
  TextEditingController? _motoboyLojaFieldController;
  bool _gerandoLoja = false;

  RelatorioRestaurante _relatorio = RelatorioRestaurante.vazio();
  bool _gerandoPdf = false;
  String? _gerandoPdfMotoboyUid;
  bool _zerandoTodos = false;

  List<DiaFinanceiro> _historicoFinanceiro = [];
  List<MesFechado> _mesesFechados = [];
  bool _zerandoTudo = false;

  List<({String uid, double lat, double lng, DateTime? atualizadoEm})>
  _localizacoes = [];

  String get _uid => ChatService.meuUid!;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeLojaController.dispose();
    _merchantIdController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final bairros = await RestauranteService.listarBairros(_uid);
    final vinculados = await RestauranteService.listarMotoboysVinculados(_uid);
    final todos = await RestauranteService.listarTodosMotoboys();
    final usarTaxa = await RestauranteService.getUsarTaxaMotocaPremium(_uid);
    final lojas = await RestauranteLojasApi.listar();
    final nomeConta = await RestauranteService.getNomeConta(_uid);
    final relatorio = await RestauranteRelatorioApi.buscar();
    final historicoFinanceiro =
        await RestauranteFinanceiroApi.buscarHistorico();
    final mesesFechados = await RestauranteFinanceiroApi.listarFechados();
    final localizacoes = await LocalizacaoApi.buscarVarios(
      vinculados.map((m) => m.uid).toList(),
    );
    if (!mounted) return;
    setState(() {
      _bairros = bairros;
      _vinculados = vinculados;
      _todosMotoboys = todos;
      _historicoFinanceiro = historicoFinanceiro;
      _mesesFechados = mesesFechados;
      _localizacoes = localizacoes;
      _usarTaxaMotocaPremium = usarTaxa;
      _lojas = lojas;
      _nomeConta = nomeConta;
      _relatorio = relatorio;
      if (_nomeLojaController.text.isEmpty)
        _nomeLojaController.text = nomeConta;
      _carregando = false;
    });
  }

  /// Nome de um motoboy pelo uid — tenta primeiro entre os vinculados
  /// (mais provável), senão entre todos os motoboys do app.
  String _nomeDoMotoboy(String uid) {
    final vinculo = _vinculados.where((m) => m.uid == uid).toList();
    if (vinculo.isNotEmpty) return vinculo.first.nome;
    final todos = _todosMotoboys.where((m) => m['uid'] == uid).toList();
    if (todos.isNotEmpty) return todos.first['nome'] as String;
    return uid;
  }

  Future<void> _baixarRelatorioPdf() async {
    setState(() => _gerandoPdf = true);
    try {
      await gerarEBaixarRelatorioPdf(
        nomeRestaurante: _nomeConta.isNotEmpty ? _nomeConta : 'Motoca Premium',
        relatorio: _relatorio,
        nomeDoMotoboy: _nomeDoMotoboy,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não consegui gerar o PDF: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _gerandoPdf = false);
    }
  }

  /// Baixa o PDF de só um motoboy — mesmo gerador do relatório geral, só
  /// que com a lista filtrada pra um único motoboy.
  Future<void> _baixarPdfMotoboy(MotoboyRelatorio m) async {
    setState(() => _gerandoPdfMotoboyUid = m.motoboyUid);
    try {
      await gerarEBaixarRelatorioPdf(
        nomeRestaurante: _nomeConta.isNotEmpty ? _nomeConta : 'Motoca Premium',
        relatorio: RelatorioRestaurante(
          motoboys: [m],
          totalHojeSaidas: m.saidasHoje,
          totalHojeValor: m.totalHoje,
        ),
        nomeDoMotoboy: _nomeDoMotoboy,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não consegui gerar o PDF: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _gerandoPdfMotoboyUid = null);
    }
  }

  /// Zera manualmente o período "hoje" de TODOS os motoboys desse
  /// relatório de uma vez — pra quando o restaurante quer fechar o dia
  /// sem esperar cada motoboy apertar o próprio "Zerar o dia" no
  /// Financeiro dele (Fase 12.1).
  Future<void> _zerarDiaTodos() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.power_settings_new, color: Colors.red),
            SizedBox(width: 10),
            Text('Zerar o dia?'),
          ],
        ),
        content: Text(
          'Zera o "hoje" de todos os ${_relatorio.motoboys.length} motoboys nesse relatório (R\$ ${_relatorio.totalHojeValor.toStringAsFixed(2)} no total). O histórico continua salvo, só some da contagem de hoje.',
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Zerar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _zerandoTodos = true);
    try {
      final resultados = await Future.wait(
        _relatorio.motoboys.map(
          (m) => RestauranteRelatorioApi.zerarDia(m.motoboyUid),
        ),
      );
      if (!mounted) return;
      if (resultados.any((ok) => !ok)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não consegui zerar tudo agora. Tente de novo.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await _carregar();
    } finally {
      if (mounted) setState(() => _zerandoTodos = false);
    }
  }

  Future<void> _alternarUsarTaxa(bool valor) async {
    setState(() => _usarTaxaMotocaPremium = valor);
    await RestauranteService.definirUsarTaxaMotocaPremium(_uid, valor);
  }

  /// Gera um Merchant/Client ID/Secret novo pra um motoboy já vinculado —
  /// self-service da mesma coisa que o Admin faz em admin_motoboys_page.dart,
  /// só que restrito aos motoboys deste restaurante (ver Fase 11.3 do plano).
  Future<void> _gerarCredenciaisLoja() async {
    final motoboyUid = _motoboyLojaSelecionadoUid;
    final nomeRestaurante = _nomeLojaController.text.trim();
    final merchantId = _merchantIdController.text.trim();

    if (motoboyUid == null || nomeRestaurante.isEmpty || merchantId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preenche o motoboy, o nome do restaurante e o Merchant ID.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _gerandoLoja = true);
    try {
      final resultado = await RestauranteLojasApi.criar(
        merchantId: merchantId,
        motoboyUid: motoboyUid,
        nomeRestaurante: nomeRestaurante,
      );
      if (!mounted) return;
      await _mostrarCredenciaisGeradas(
        clientId: resultado['clientId'] as String,
        clientSecret: resultado['clientSecret'] as String,
      );
      _merchantIdController.clear();
      _motoboyLojaFieldController?.clear();
      setState(() => _motoboyLojaSelecionadoUid = null);
      await _carregar();
    } on RestauranteLojasApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.mensagem),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _gerandoLoja = false);
    }
  }

  Future<void> _mostrarCredenciaisGeradas({
    required String clientId,
    required String clientSecret,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.green),
            SizedBox(width: 10),
            Text('Credenciais geradas!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copia e cola isso nos campos "Client ID" e "Client Secret" da tela de Entregadores, na Saipos. O Secret não aparece de novo depois.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _campoCopiavel('Client ID', clientId),
            const SizedBox(height: 10),
            _campoCopiavel('Client Secret', clientSecret),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Fechar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoCopiavel(String rotulo, String valor) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: valor));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$rotulo copiado!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rotulo,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    valor,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.copy, color: Colors.white38, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Desativa uma credencial (não apaga de verdade, ver
  /// backend/src/routes/restauranteLojas.ts) — some da lista e para de
  /// funcionar na Saipos na hora. Pede confirmação antes porque revoga
  /// acesso de um motoboy de verdade.
  Future<void> _confirmarDesativarLoja(int id) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 10),
            Text('Desativar credencial?'),
          ],
        ),
        content: const Text(
          'A credencial para de funcionar na Saipos na hora e some dessa lista. O histórico de pedidos já feitos com ela continua salvo nos relatórios.',
          style: TextStyle(color: Colors.white70),
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
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmado == true) await _removerLoja(id);
  }

  /// Busca de novo o Client ID/Secret de uma credencial já existente e
  /// mostra no mesmo dialog usado ao gerar (o secret só aparece uma vez).
  Future<void> _verCredenciais(int id) async {
    try {
      final dados = await RestauranteLojasApi.verCredenciais(id);
      if (!mounted) return;
      await _mostrarCredenciaisGeradas(
        clientId: dados['clientId'] as String,
        clientSecret: dados['clientSecret'] as String,
      );
    } on RestauranteLojasApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.mensagem),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removerLoja(int id) async {
    try {
      await RestauranteLojasApi.remover(id);
      await _carregar();
    } on RestauranteLojasApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.mensagem),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editarBairro({Bairro? bairro}) async {
    final nomeController = TextEditingController(text: bairro?.nome ?? '');
    final taxaController = TextEditingController(
      text: bairro != null ? bairro.taxa.toStringAsFixed(2) : '',
    );

    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(bairro == null ? 'Novo bairro' : 'Editar bairro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomeController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nome do bairro',
                filled: true,
                fillColor: const Color(0xFF1B2435),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: taxaController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Taxa de entrega (R\$)',
                filled: true,
                fillColor: const Color(0xFF1B2435),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Salvar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (salvou != true) return;
    final nome = nomeController.text.trim();
    final taxa =
        double.tryParse(taxaController.text.trim().replaceAll(',', '.')) ?? 0;
    nomeController.dispose();
    taxaController.dispose();
    if (nome.isEmpty) return;

    await RestauranteService.salvarBairro(
      _uid,
      id: bairro?.id,
      nome: nome,
      taxa: taxa,
    );
    await _carregar();
  }

  Future<void> _removerBairro(Bairro bairro) async {
    await RestauranteService.removerBairro(_uid, bairro.id);
    await _carregar();
  }

  /// Abre o diálogo de cadastrar vários bairros de uma vez (escolhe
  /// cidade, busca no OpenStreetMap, marca quais quer) — ver
  /// lib/restaurante/dialog_bairros_cidade.dart.
  Future<void> _adicionarBairrosEmLote() async {
    final salvou = await mostrarDialogAdicionarBairrosPorCidade(context, _uid);
    if (salvou) await _carregar();
  }

  Future<void> _vincularMotoboy() async {
    final uid = _motoboySelecionadoUid;
    if (uid == null) return;
    final motoboy = _todosMotoboys.firstWhere((m) => m['uid'] == uid);

    setState(() => _vinculando = true);
    try {
      await RestauranteService.vincularMotoboy(
        _uid,
        motoboyUid: uid,
        nome: motoboy['nome'] as String,
        email: motoboy['email'] as String,
      );
      _motoboyFieldController?.clear();
      setState(() => _motoboySelecionadoUid = null);
      await _carregar();
    } finally {
      if (mounted) setState(() => _vinculando = false);
    }
  }

  Future<void> _desvincularMotoboy(MotoboyVinculado m) async {
    await RestauranteService.desvincularMotoboy(_uid, m.uid);
    await _carregar();
  }

  /// Abre o mapa nativo (Google Maps/Apple Maps via link, sem SDK
  /// embutido) na última posição salva desse motoboy — ver
  /// lib/localizacao_api.dart. Não usa GPS nenhum aqui, só lê o que o
  /// motoboy já salvou no Firestore.
  Future<void> _abrirLocalizacaoMotoboy(MotoboyVinculado m) async {
    final localizacao = await LocalizacaoApi.buscar(m.uid);
    if (!mounted) return;
    if (localizacao == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${m.nome} ainda não tem localização salva — precisa estar online no app.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${localizacao.lat},${localizacao.lng}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não consegui abrir o mapa.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _itemMotoboyVinculado(MotoboyVinculado m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.two_wheeler, color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.nome,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  m.email,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _abrirLocalizacaoMotoboy(m),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.location_on_outlined,
                color: Colors.blue,
                size: 18,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _desvincularMotoboy(m),
            child: const Icon(
              Icons.delete_outline,
              color: Colors.red,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  static const _itensNav = [
    (icone: Icons.storefront, rotulo: 'Painel do restaurante'),
    (icone: Icons.bar_chart, rotulo: 'Relatório'),
    (icone: Icons.payments_outlined, rotulo: 'Financeiro'),
    (icone: Icons.location_on_outlined, rotulo: 'Localização'),
  ];

  @override
  Widget build(BuildContext context) {
    final motoboysDisponiveis = _todosMotoboys
        .where((m) => !_vinculados.any((v) => v.uid == m['uid']))
        .toList();

    final conteudos = [
      _abaConfiguracao(motoboysDisponiveis),
      _abaRelatorio(),
      _abaFinanceiro(),
      _abaLocalizacao(),
    ];

    final larguraEstreita = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator(color: Colors.blue))
            : Column(
                children: [
                  _cabecalho(),
                  if (larguraEstreita) _navEstreita(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!larguraEstreita) _menuLateral(),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _carregar,
                            child: conteudos[_navIndex],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Barra de topo: logo/marca do app + notificações (decorativo, ainda sem
  /// sistema de notificação de verdade) + chip de perfil com o nome do
  /// restaurante — tocar nele abre o menu de sair.
  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.two_wheeler, color: Colors.blue, size: 26),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Motoca Premium',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Mais entregas, mais resultados',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.notifications_outlined, color: Colors.white54),
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            color: const Color(0xFF111827),
            onSelected: (v) async {
              if (v == 'sair') {
                await DB.limparSessao();
                widget.onLogout();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'sair',
                child: Row(children: [
                  Icon(Icons.logout, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Text('Sair'),
                ]),
              ),
            ],
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue,
                  child: Text(
                    (_nomeConta.isNotEmpty ? _nomeConta[0] : 'R').toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nomeConta.isNotEmpty ? _nomeConta : 'Restaurante',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const Text('Restaurante',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Menu lateral fixo (telas largas — Web/desktop), substitui as antigas
  /// abas no topo.
  Widget _menuLateral() {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _itensNav.length; i++) _itemMenuLateral(i),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text('Sistema online', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Motoca Premium v1.0', style: TextStyle(color: Colors.white24, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _itemMenuLateral(int i) {
    final selecionado = _navIndex == i;
    final item = _itensNav[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selecionado ? Colors.blue.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _navIndex = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(item.icone, size: 20, color: selecionado ? Colors.blue : Colors.white54),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.rotulo,
                    style: TextStyle(
                      color: selecionado ? Colors.white : Colors.white54,
                      fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Navegação em telas estreitas (celular) — uma fileira de abas roláveis
  /// no topo, no lugar do menu lateral (que não cabe numa tela pequena).
  Widget _navEstreita() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (var i = 0; i < _itensNav.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(_itensNav[i].rotulo),
                avatar: Icon(_itensNav[i].icone, size: 16),
                selected: _navIndex == i,
                onSelected: (_) => setState(() => _navIndex = i),
                selectedColor: Colors.blue.withValues(alpha: 0.25),
                backgroundColor: const Color(0xFF111827),
                labelStyle: TextStyle(color: _navIndex == i ? Colors.white : Colors.white54),
              ),
            ),
        ],
      ),
    );
  }

  /// Layout em duas colunas em telas largas (Web/desktop, igual ao design
  /// novo do painel), empilhado em uma coluna só em telas estreitas
  /// (celular) — mesmo conteúdo dos dois jeitos.
  Widget _abaConfiguracao(List<Map<String, dynamic>> motoboysDisponiveis) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final esquerda = _colunaTaxas();
        final direita = _colunaMotoboysCredenciais(motoboysDisponiveis);

        if (constraints.maxWidth < 800) {
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [...esquerda, const SizedBox(height: 28), ...direita],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: esquerda),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: direita),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Coluna esquerda: taxas por bairro + dica.
  List<Widget> _colunaTaxas() {
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.swap_horiz, color: Colors.amber, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usar taxas do Motoca Premium por bairro',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Quando ligado, a taxa do bairro configurado aqui vale sempre — mesmo que o pedido chegue com outro valor.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: _usarTaxaMotocaPremium,
              onChanged: _alternarUsarTaxa,
              activeColor: Colors.amber,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Taxas por bairro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: _adicionarBairrosEmLote,
            icon: const Icon(
              Icons.playlist_add,
              color: Colors.blue,
              size: 18,
            ),
            label: const Text('Vários', style: TextStyle(color: Colors.blue)),
          ),
          TextButton.icon(
            onPressed: () => _editarBairro(),
            icon: const Icon(Icons.add, color: Colors.blue, size: 18),
            label: const Text(
              'Adicionar',
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_bairros.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text(
              'Nenhum bairro cadastrado ainda.',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        )
      else
        ..._bairros.map(
          (b) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Colors.blue,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(b.nome, style: const TextStyle(fontSize: 15)),
                ),
                Text(
                  'R\$ ${b.taxa.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _editarBairro(bairro: b),
                  child: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _removerBairro(b),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.two_wheeler, color: Colors.blue, size: 22),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dica', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 2),
                  Text(
                    'Mantenha as taxas por bairro sempre atualizadas para evitar surpresas nos pedidos e garantir uma melhor experiência para seus clientes e motoboys.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Coluna direita: motoboys vinculados + credenciais Saipos.
  List<Widget> _colunaMotoboysCredenciais(List<Map<String, dynamic>> motoboysDisponiveis) {
    return [
      const Text(
        'Motoboys',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelecionarMotoboy(
                opcoes: motoboysDisponiveis
                    .map(
                      (m) => OpcaoMotoboy(
                        uid: m['uid'] as String,
                        nome: m['nome'] as String,
                        email: m['email'] as String,
                      ),
                    )
                    .toList(),
                onSelecionado: (v) =>
                    setState(() => _motoboySelecionadoUid = v),
                onControllerReady: (c) => _motoboyFieldController = c,
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (_motoboySelecionadoUid == null || _vinculando)
                  ? null
                  : _vincularMotoboy,
              child: _vinculando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Vincular'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (_vinculados.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text(
              'Nenhum motoboy vinculado ainda.',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        )
      else
        ..._vinculados.map(_itemMotoboyVinculado),
      const SizedBox(height: 28),
      const Text(
        'Credenciais Saipos',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      const Text(
        'Gere o Client ID/Secret pra colar na Saipos (Entregadores > Usar serviço de entrega) — escolha um motoboy já vinculado acima.',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
      const SizedBox(height: 12),
      _formularioLoja(),
      const SizedBox(height: 12),
      if (_lojas.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text(
              'Nenhuma credencial gerada ainda.',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        )
      else
        ..._lojas.map(_itemLoja),
    ];
  }

  /// Mapa (OpenStreetMap via flutter_map, sem custo/API key) com um
  /// marcador por motoboy vinculado que já tem posição salva — ver
  /// lib/localizacao_api.dart (reaproveita o GPS do odômetro, nunca liga
  /// rastreamento novo). Verde = atualizou nos últimos 10 min, cinza =
  /// mais antigo que isso.
  Widget _abaLocalizacao() {
    if (_localizacoes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Nenhum motoboy com localização salva ainda — precisa estar online no app pra aparecer aqui.',
                style: TextStyle(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    final centroLat =
        _localizacoes.map((l) => l.lat).reduce((a, b) => a + b) /
        _localizacoes.length;
    final centroLng =
        _localizacoes.map((l) => l.lng).reduce((a, b) => a + b) /
        _localizacoes.length;

    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(centroLat, centroLng),
        initialZoom: _localizacoes.length == 1 ? 15 : 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'motopremium.myapp',
        ),
        MarkerLayer(
          markers: _localizacoes.map((l) {
            final atualizado =
                l.atualizadoEm != null &&
                DateTime.now().difference(l.atualizadoEm!) <=
                    const Duration(minutes: 10);
            final cor = atualizado ? Colors.green : Colors.blueGrey;
            return Marker(
              point: LatLng(l.lat, l.lng),
              width: 130,
              height: 60,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _nomeDoMotoboy(l.uid),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.location_on, color: cor, size: 30),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _zerarTudo() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 10),
            Text('Zerar tudo?'),
          ],
        ),
        content: const Text(
          'Isso APAGA todo o histórico de "Meses fechados" (não fica guardado em lugar nenhum) e zera o período atual na hora. Os pedidos/entregas em si continuam salvos, só o resumo financeiro é apagado.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Zerar tudo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _zerandoTudo = true);
    try {
      final ok = await RestauranteFinanceiroApi.zerarTudo();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não consegui zerar agora. Tente de novo.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Financeiro zerado!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _zerandoTudo = false);
    }
  }

  Widget _botaoZerarTudo() {
    final semNada = _historicoFinanceiro.isEmpty && _mesesFechados.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: (semNada || _zerandoTudo) ? null : _zerarTudo,
          icon: _zerandoTudo
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: Colors.red,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.delete_forever, color: Colors.red, size: 16),
          label: const Text(
            'ZERAR TUDO',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _secaoMesesFechados() {
    if (_mesesFechados.isEmpty) return [];
    return [
      const SizedBox(height: 24),
      const Text(
        'Meses fechados',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      const Text(
        'Fecha sozinho todo início de mês — o período atual acima é sempre o mês corrente.',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      ),
      const SizedBox(height: 12),
      ..._mesesFechados.map(_cardMesFechado),
    ];
  }

  Widget _cardMesFechado(MesFechado m) {
    String dataStr(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${dataStr(m.periodoInicio)} até ${dataStr(m.periodoFim)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'R\$ ${m.totalVendas.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${m.saidas} saídas · Crédito R\$ ${m.totalCredito.toStringAsFixed(2)} · Débito R\$ ${m.totalDebito.toStringAsFixed(2)} · Dinheiro R\$ ${m.totalDinheiro.toStringAsFixed(2)} · Pix R\$ ${m.totalPix.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _abaFinanceiro() {
    if (_historicoFinanceiro.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Nenhum dado financeiro registrado ainda.',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ),
          if (_mesesFechados.isNotEmpty) _botaoZerarTudo(),
          ..._secaoMesesFechados(),
        ],
      );
    }

    final totalVendas = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => s + d.totalVendas,
    );
    final totalCredito = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => s + d.totalCredito,
    );
    final totalDebito = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => s + d.totalDebito,
    );
    final totalCartao = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => s + d.totalCartao,
    );
    final totalDinheiro = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => s + d.totalDinheiro,
    );
    final totalPix = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => s + d.totalPix,
    );
    final totalOutros = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => s + d.totalOutros,
    );
    final maiorValorDia = _historicoFinanceiro.fold<double>(
      0,
      (s, d) => d.totalVendas > s ? d.totalVendas : s,
    );

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bar_chart, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'TOTAL DO PERÍODO',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'R\$ ${totalVendas.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Últimos ${_historicoFinanceiro.length} dias com movimento',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _tilePagamento(
                Icons.credit_card,
                'Crédito',
                totalCredito,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tilePagamento(
                Icons.credit_card_outlined,
                'Débito',
                totalDebito,
                Colors.indigo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _tilePagamento(
                Icons.payments_outlined,
                'Dinheiro',
                totalDinheiro,
                Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tilePagamento(
                Icons.qr_code,
                'Pix',
                totalPix,
                Colors.teal,
              ),
            ),
          ],
        ),
        if (totalCartao > 0) ...[
          const SizedBox(height: 10),
          _tilePagamento(
            Icons.credit_card,
            'Cartão (não especificado)',
            totalCartao,
            Colors.blueGrey,
          ),
        ],
        if (totalOutros > 0) ...[
          const SizedBox(height: 10),
          _tilePagamento(
            Icons.more_horiz,
            'Outros',
            totalOutros,
            Colors.white38,
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Vendas por dia',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          height: 220,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
          ),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maiorValorDia <= 0 ? 10 : maiorValorDia * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final dia = _historicoFinanceiro[group.x];
                    return BarTooltipItem(
                      'R\$ ${dia.totalVendas.toStringAsFixed(2)}',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= _historicoFinanceiro.length)
                        return const SizedBox.shrink();
                      final d = _historicoFinanceiro[i].data;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barGroups: [
                for (var i = 0; i < _historicoFinanceiro.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: _historicoFinanceiro[i].totalVendas,
                        color: Colors.green,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _botaoZerarTudo(),
        ..._secaoMesesFechados(),
      ],
    );
  }

  Widget _abaRelatorio() {
    if (_relatorio.motoboys.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Nenhuma entrega registrada ainda pra esse restaurante.',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'HOJE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'R\$ ${_relatorio.totalHojeValor.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_relatorio.totalHojeSaidas} saídas no total',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 2),
              const Text(
                'Desde o último "Zerar o dia" de cada motoboy.',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _cardFormasPagamento(),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.blue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _gerandoPdf ? null : _baixarRelatorioPdf,
            icon: _gerandoPdf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.blue,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Colors.blue,
                    size: 18,
                  ),
            label: const Text(
              'BAIXAR PDF',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _zerandoTodos ? null : _zerarDiaTodos,
            icon: _zerandoTodos
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.red,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.power_settings_new,
                    color: Colors.red,
                    size: 18,
                  ),
            label: const Text(
              'ZERAR O DIA',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Por motoboy',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._relatorio.motoboys.map(_cardMotoboyRelatorio),
      ],
    );
  }

  Widget _cardFormasPagamento() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Total de vendas',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                'R\$ ${_relatorio.totalVendas.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _tilePagamento(
                  Icons.credit_card,
                  'Crédito',
                  _relatorio.totalCredito,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tilePagamento(
                  Icons.credit_card_outlined,
                  'Débito',
                  _relatorio.totalDebito,
                  Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _tilePagamento(
                  Icons.payments_outlined,
                  'Dinheiro',
                  _relatorio.totalDinheiro,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tilePagamento(
                  Icons.qr_code,
                  'Pix',
                  _relatorio.totalPix,
                  Colors.teal,
                ),
              ),
            ],
          ),
          if (_relatorio.totalCartao > 0) ...[
            const SizedBox(height: 10),
            _tilePagamento(
              Icons.credit_card,
              'Cartão (não especificado)',
              _relatorio.totalCartao,
              Colors.blueGrey,
            ),
          ],
          if (_relatorio.totalOutros > 0) ...[
            const SizedBox(height: 10),
            _tilePagamento(
              Icons.more_horiz,
              'Outros',
              _relatorio.totalOutros,
              Colors.white38,
            ),
          ],
        ],
      ),
    );
  }

  Widget _tilePagamento(
    IconData icone,
    String rotulo,
    double valor,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 14),
              const SizedBox(width: 4),
              Text(
                rotulo,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'R\$ ${valor.toStringAsFixed(2)}',
            style: TextStyle(
              color: cor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardMotoboyRelatorio(MotoboyRelatorio m) {
    final gerandoPdf = _gerandoPdfMotoboyUid == m.motoboyUid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.two_wheeler, color: Colors.orange, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _nomeDoMotoboy(m.motoboyUid),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'R\$ ${m.totalHoje.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${m.saidasHoje} saídas hoje · ${m.saidasHistorico} no total',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          if (m.comandas.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 10),
            ...m.comandas.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_outlined,
                      color: Colors.white24,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Comanda ${c.referencia}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      'R\$ ${c.taxa.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: gerandoPdf ? null : () => _baixarPdfMotoboy(m),
              icon: gerandoPdf
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Colors.blue,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Colors.blue,
                      size: 16,
                    ),
              label: const Text(
                'BAIXAR PDF',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formularioLoja() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Motoboy',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          SelecionarMotoboy(
            opcoes: _vinculados
                .map(
                  (m) => OpcaoMotoboy(uid: m.uid, nome: m.nome, email: m.email),
                )
                .toList(),
            onSelecionado: (v) =>
                setState(() => _motoboyLojaSelecionadoUid = v),
            onControllerReady: (c) => _motoboyLojaFieldController = c,
            hint: 'Buscar motoboy vinculado',
          ),
          const SizedBox(height: 14),

          const Text(
            'Nome do restaurante',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nomeLojaController,
            decoration: InputDecoration(
              hintText: 'Ex: Treduarte Pizzaria',
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),

          const Text(
            'Merchant ID (da Saipos)',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _merchantIdController,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ex: 38f48430-6e62-4273-8510-6ea638d8b524',
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: (_vinculados.isEmpty || _gerandoLoja)
                  ? null
                  : _gerarCredenciaisLoja,
              child: _gerandoLoja
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'GERAR CREDENCIAIS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          if (_vinculados.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Vincula um motoboy acima antes de gerar credenciais.',
              style: TextStyle(color: Colors.orange, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemLoja(Map<String, dynamic> loja) {
    final motoboyUid = loja['motoboyUid'] as String?;
    final vinculo = _vinculados.where((m) => m.uid == motoboyUid).toList();
    final nomeMotoboy = vinculo.isNotEmpty
        ? vinculo.first.nome
        : (motoboyUid ?? '—');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _verCredenciais(loja['id'] as int),
            child: const Icon(Icons.vpn_key_outlined, color: Colors.blue, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeMotoboy,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  loja['nomeRestaurante'] as String,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _confirmarDesativarLoja(loja['id'] as int),
            child: const Icon(
              Icons.block,
              color: Colors.red,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
