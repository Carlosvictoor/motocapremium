// Aba "Pedidos": total das taxas, botão de escanear e a lista de pedidos
// deste motoboy — os já aceitos e os que já nasceram atribuídos a ele
// (aparecem com botão ACEITAR, ver PedidoCard.disponivel), sem precisar
// escanear. Escanear o código de barras continua funcionando como
// fallback/atalho pra pegar vários de uma vez (ver
// pedidos_api.dart/escanear e backend/src/routes/deliveriesScan.ts).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../integracoes_api.dart';
import '../restaurante/taxa_override_service.dart';
import 'codigo_confirmacao_dialog.dart';
import 'codigo_confirmacao_externa_dialog.dart';
import 'entrega_externa_model.dart';
import 'pedido_card.dart';
import 'pedidos_api.dart';
import 'pedidos_models.dart';
import 'scanner_page.dart';

class PedidosTab extends StatefulWidget {
  /// Chamado quando uma entrega é finalizada, pra registrar a taxa como uma
  /// Saída no Financeiro/Home existente (ver MainShell.registrarSaida).
  final void Function({required String taxa, required String referencia}) onEntregaFinalizada;

  /// Chamado toda vez que a lista de pedidos recarrega, avisando se tem
  /// alguma entrega em andamento — usado por MainShell pra decidir a
  /// frequência de salvar a localização (Fase 13): mais frequente com
  /// pedido ativo, no máximo 1x a cada 3 minutos sem nenhum.
  final void Function(bool temAtivo)? onPedidoAtivoMudou;

  const PedidosTab({super.key, required this.onEntregaFinalizada, this.onPedidoAtivoMudou});

  @override
  State<PedidosTab> createState() => _PedidosTabState();
}

class _PedidosTabState extends State<PedidosTab> {
  bool _carregando = true;
  String? _erro;
  List<Pedido> _pedidos = [];
  double _totalTaxas = 0;
  int? _finalizandoId;
  int? _aceitandoId;
  List<IntegracaoExterna> _integracoes = [];
  String? _finalizandoExternaKey;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resultado = await PedidosApi.listar();
      final integracoes = await IntegracoesApi.listar();

      // Limpa o cache de bairros/config a cada recarregada (ex.: puxar pra
      // atualizar) pra refletir qualquer mudança recente feita no painel do
      // restaurante, sem precisar reiniciar o app.
      TaxaOverrideService.limparCache();

      final pedidos = await Future.wait(resultado.pedidos.map((p) async {
        final taxa = await TaxaOverrideService.taxaEfetiva(
          restauranteUid: p.restauranteUid,
          endereco: p.endereco,
          taxaOriginal: p.taxaMotoboy,
        );
        return taxa == p.taxaMotoboy ? p : p.copyWithTaxa(taxa);
      }));

      final integracoesComTaxa = await Future.wait(integracoes.map((integracao) async {
        final pedidosIntegracao = await Future.wait(integracao.pedidos.map((p) async {
          final taxa = await TaxaOverrideService.taxaEfetiva(
            restauranteUid: integracao.restauranteUid,
            endereco: p.endereco,
            taxaOriginal: p.taxa,
          );
          return taxa == p.taxa ? p : p.copyWithTaxa(taxa);
        }));
        return integracao.copyWithPedidos(pedidosIntegracao);
      }));

      // O total de taxas vem somado do backend com o valor bruto de cada
      // pedido — como a sobreposição por bairro pode ter trocado a taxa de
      // alguns aqui no app, recalcula pra bater com o que os cards mostram.
      // Inclui também as taxas das "Outras entregas" (integrações externas)
      // — antes só contava os pedidos da Saipos, deixando de fora o que o
      // motoboy tem a receber dos outros sistemas.
      final totalTaxas = pedidos.fold<double>(0, (soma, p) => soma + p.taxaMotoboy) +
          integracoesComTaxa.expand((i) => i.pedidos).fold<double>(0, (soma, p) => soma + p.taxa);

      // Pedidos ainda DISPONIVEL (atribuídos a este motoboy, aguardando ele
      // tocar em ACEITAR) aparecem primeiro, antes dos já aceitos.
      pedidos.sort((a, b) => (a.disponivel == b.disponivel) ? 0 : (a.disponivel ? -1 : 1));

      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _totalTaxas = totalTaxas;
        _integracoes = integracoesComTaxa;
        _carregando = false;
      });
      widget.onPedidoAtivoMudou?.call(_temAlgumPedidoAtivo(pedidos, integracoesComTaxa));
    } on PedidosApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    } catch (_) {
      // Qualquer outro erro inesperado (ex.: falha ao calcular a
      // sobreposição de taxa por bairro) não deve deixar a aba presa
      // girando pra sempre — mostra um erro genérico em vez disso.
      if (!mounted) return;
      setState(() {
        _erro = 'Não consegui carregar os pedidos agora. Tente de novo.';
        _carregando = false;
      });
    }
  }

  /// Tem alguma entrega em andamento (aceita mas ainda não finalizada, ou
  /// alguma de integração externa esperando finalizar)? Usado só pra
  /// avisar o MainShell (ver [onPedidoAtivoMudou]), não afeta a tela.
  bool _temAlgumPedidoAtivo(List<Pedido> pedidos, List<IntegracaoExterna> integracoes) {
    final temSaipos = pedidos.any((p) => p.status == 'ACEITA' || p.status == 'RETIRADA' || p.status == 'EM_ENTREGA');
    final temExterna = integracoes.any((i) => i.pedidos.isNotEmpty);
    return temSaipos || temExterna;
  }

  Future<void> _abrirScanner() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (codigo == null || !mounted) return;
    await _procurarPedido(codigo);
  }

  /// Mostra "Procurando e aceitando pedido...", chama o backend (que já acha
  /// E aceita a entrega numa tacada só) e depois mostra o resultado (card do
  /// pedido aceito ou erro — ex.: já aceito por outro motoboy).
  Future<void> _procurarPedido(String codigo) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogCarregando(texto: 'Procurando e aceitando pedido...'),
    );

    try {
      final pedido = await PedidosApi.escanear(codigo);
      if (!mounted) return;
      Navigator.pop(context); // fecha o "Procurando..."
      await _mostrarPedidoAceito(pedido);
      await _carregar();
    } on PedidosApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mostrarErro(e.mensagem);
    }
  }

  Future<void> _mostrarPedidoAceito(Pedido pedido) async {
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(16),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('Entrega aceita!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ),
              PedidoCard(pedido: pedido),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Fechar', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  /// Abre o Google Maps com uma rota passando pelo endereço de todas as
  /// entregas aceitas (em ordem), pra o motoboy seguir uma atrás da outra
  /// sem precisar abrir mapa pedido por pedido — inclui tanto os pedidos
  /// da Saipos quanto os de integrações externas ("Outras entregas").
  Future<void> _abrirRotaCompleta() async {
    final todosEnderecos = [
      ..._pedidos.map((p) => p.endereco).whereType<String>(),
      ..._integracoes.expand((i) => i.pedidos).map((p) => p.endereco),
    ].where((e) => e.trim().isNotEmpty).toList();

    if (todosEnderecos.isEmpty) {
      _mostrarErro('Nenhuma entrega com endereço pra traçar rota.');
      return;
    }

    // O link de rota do Google Maps só aceita até 9 paradas intermediárias
    // no app mobile (destino + waypoints) — passar disso faz o Maps abrir e
    // fechar sozinho (erro silencioso) em vez de mostrar a rota. Limita a
    // 10 endereços (9 waypoints + 1 destino) e avisa se sobrou entrega de fora.
    const maxEnderecos = 10;
    final enderecos = todosEnderecos.length > maxEnderecos
        ? todosEnderecos.sublist(0, maxEnderecos)
        : todosEnderecos;

    final destino = Uri.encodeComponent(enderecos.last);
    final paradas = enderecos.length > 1
        ? enderecos.sublist(0, enderecos.length - 1).map(Uri.encodeComponent).join('|')
        : '';

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destino'
      '${paradas.isNotEmpty ? '&waypoints=$paradas' : ''}'
      '&travelmode=driving',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      final sobrando = todosEnderecos.length - enderecos.length;
      if (sobrando > 0 && mounted) {
        _mostrarErro(
          'A rota só coube $maxEnderecos entregas (limite do Google Maps) — faltam $sobrando, abra o mapa delas separado no card de cada uma.',
        );
      }
    } else if (mounted) {
      _mostrarErro('Não consegui abrir o mapa.');
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensagem),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Aceita um pedido que já apareceu atribuído a este motoboy (nasceu com
  /// motoboy_uid dele, ver backend/src/routes/logisticsDelivery.ts) — sem
  /// precisar escanear a comanda física.
  Future<void> _aceitar(Pedido pedido) async {
    setState(() => _aceitandoId = pedido.id);
    try {
      await PedidosApi.aceitar(pedido.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Entrega aceita!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
      await _carregar();
    } on PedidosApiException catch (e) {
      if (!mounted) return;
      _mostrarErro(e.mensagem);
    } finally {
      if (mounted) setState(() => _aceitandoId = null);
    }
  }

  /// Finaliza a entrega. Se o pedido exigir código de confirmação (a Saipos
  /// manda isso por pedido), abre o dialog do código primeiro — a
  /// confirmação e a finalização acontecem dentro do próprio dialog. Senão,
  /// finaliza direto.
  Future<void> _finalizar(Pedido pedido) async {
    if (pedido.confirmationCodeRequired) {
      final ok = await mostrarDialogCodigoConfirmacao(context, pedido.id, pedido.taxaMotoboy);
      if (ok == true) _aoFinalizarComSucesso(pedido);
      return;
    }

    setState(() => _finalizandoId = pedido.id);
    try {
      await PedidosApi.finalizar(pedido.id, taxaEfetiva: pedido.taxaMotoboy);
      _aoFinalizarComSucesso(pedido);
    } on PedidosApiException catch (e) {
      if (!mounted) return;
      _mostrarErro(e.mensagem);
    } finally {
      if (mounted) setState(() => _finalizandoId = null);
    }
  }

  void _aoFinalizarComSucesso(Pedido pedido) {
    widget.onEntregaFinalizada(
      taxa: pedido.taxaMotoboy.toStringAsFixed(2),
      referencia: 'Pedido #${pedido.orderDisplayId ?? pedido.orderId}${pedido.restaurante != null ? ' - ${pedido.restaurante}' : ''}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Entrega finalizada! Taxa registrada no Financeiro.'),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
    _carregar();
  }

  /// Chamado ao tocar em FINALIZAR num pedido de integração externa. Se o
  /// pedido tiver um código de confirmação (`localizador` — comum em
  /// pedidos de agregadores tipo iFood/99), abre o dialog pra digitar (com
  /// opção de pular); senão, finaliza direto como antes.
  Future<void> _aoTocarFinalizarExterna(IntegracaoExterna integracao, EntregaExterna p) async {
    if (p.localizador.trim().isEmpty) {
      await _finalizarExterna(integracao, p);
      return;
    }
    final prosseguir = await mostrarDialogCodigoExterno(context, p.localizador);
    if (prosseguir == true) await _finalizarExterna(integracao, p);
  }

  /// Finaliza uma entrega de integração externa: registra a taxa no
  /// Financeiro (mesmo callback que os pedidos da Saipos usam) e avisa o
  /// backend pra esse pedido parar de aparecer na lista (o sistema externo
  /// em si não recebe nada — ele é só leitura).
  Future<void> _finalizarExterna(IntegracaoExterna integracao, EntregaExterna p) async {
    final key = '${integracao.id}:${p.pedido}';
    setState(() => _finalizandoExternaKey = key);
    try {
      final ok = await IntegracoesApi.finalizar(
        integracao.id,
        p.pedido,
        taxa: p.taxa,
        valorTotal: p.valorCobrar,
        formaPagamento: p.formaPagamento,
      );
      if (!ok) {
        if (!mounted) return;
        _mostrarErro('Não consegui finalizar agora. Tente de novo.');
        return;
      }
      widget.onEntregaFinalizada(
        taxa: p.taxa.toStringAsFixed(2),
        referencia: 'Pedido #${p.pedido}${p.loja.isNotEmpty ? ' - ${p.loja}' : ' - ${integracao.nome}'}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Entrega finalizada! Taxa registrada no Financeiro.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
      await _carregar();
    } finally {
      if (mounted) setState(() => _finalizandoExternaKey = null);
    }
  }

  Future<void> _abrirMapaEndereco(String endereco) async {
    if (endereco.trim().isEmpty) return;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _mostrarErro('Não consegui abrir o mapa.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text('Pedidos',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),

              _totalTaxasCard(),
              const SizedBox(height: 24),

              if (_carregando)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator(color: Colors.blue)),
                )
              else if (_erro != null)
                _mensagemVazia(icone: Icons.error_outline, texto: _erro!, cor: Colors.red)
              else if (_pedidos.isEmpty)
                _mensagemVazia(
                  icone: Icons.inbox,
                  texto: 'Nenhuma entrega em andamento.\nEscaneie o código de barras de um pedido pra aceitar e ele aparecer aqui.',
                  cor: Colors.white38,
                )
              else
                ..._pedidos.map((p) => PedidoCard(
                      pedido: p,
                      aceitando: _aceitandoId == p.id,
                      onAceitar: () => _aceitar(p),
                      finalizando: _finalizandoId == p.id,
                      onFinalizar: () => _finalizar(p),
                    )),

              if (!_carregando && _integracoes.isNotEmpty) ..._secaoOutrasEntregas(),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pedidos.isNotEmpty || _integracoes.any((i) => i.pedidos.isNotEmpty)) ...[
            FloatingActionButton(
              heroTag: 'rota',
              backgroundColor: const Color(0xFF111827),
              foregroundColor: Colors.blue,
              onPressed: _abrirRotaCompleta,
              tooltip: 'Abrir rota com todas as entregas',
              child: const Icon(Icons.map_outlined),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.extended(
            heroTag: 'escanear',
            backgroundColor: Colors.blue,
            onPressed: _abrirScanner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _totalTaxasCard() {
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
          const Row(children: [
            Icon(Icons.payments, color: Colors.green, size: 20),
            SizedBox(width: 8),
            Text('TOTAL DAS TAXAS', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text('R\$ ${_totalTaxas.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green)),
        ],
      ),
    );
  }

  /// Seção "Outras entregas" — pedidos de integrações externas de leitura
  /// (outros sistemas de delivery, fora a Saipos). Só visualização: não tem
  /// botão de aceitar/finalizar, porque quem controla o status é o painel
  /// do próprio sistema externo.
  List<Widget> _secaoOutrasEntregas() {
    return [
      const SizedBox(height: 28),
      const Text('Outras entregas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      for (final integracao in _integracoes) ..._blocoIntegracao(integracao),
    ];
  }

  List<Widget> _blocoIntegracao(IntegracaoExterna integracao) {
    if (integracao.status == 'indisponivel') {
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.cloud_off, color: Colors.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${integracao.nome} indisponível no momento.',
                  style: const TextStyle(color: Colors.orange, fontSize: 13)),
            ),
          ]),
        ),
      ];
    }
    if (integracao.status == 'bloqueado') {
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.block, color: Colors.red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Bloqueado em ${integracao.nome} — fale com quem administra esse sistema.',
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ]),
        ),
      ];
    }
    if (integracao.pedidos.isEmpty) return [];
    return integracao.pedidos.map((p) => _cardEntregaExterna(integracao, p)).toList();
  }

  Widget _cardEntregaExterna(IntegracaoExterna integracao, EntregaExterna p) {
    final origem = p.loja.isNotEmpty ? p.loja : integracao.nome;
    final finalizando = _finalizandoExternaKey == '${integracao.id}:${p.pedido}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Pedido #${p.pedido}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
              child: Text(origem, style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
          if (p.cliente.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.person_outline, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(p.cliente, style: const TextStyle(color: Colors.white70, fontSize: 14))),
            ]),
          ],
          if (p.endereco.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(p.endereco, style: const TextStyle(color: Colors.white70, fontSize: 13))),
            ]),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Icon(p.pago ? Icons.check_circle_outline : Icons.money_off, color: p.pago ? Colors.green : Colors.orange, size: 16),
            const SizedBox(width: 6),
            Text(p.formaPagamento.isNotEmpty ? p.formaPagamento : 'Forma de pagamento não informada',
                style: TextStyle(color: p.pago ? Colors.white70 : Colors.orange, fontSize: 13)),
          ]),
          if (!p.pago) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text('Cobrar R\$ ${p.valorCobrar.toStringAsFixed(2)} do cliente',
                  style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Valor', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    Text('R\$ ${p.valorCobrar.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Taxa', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    Text('R\$ ${p.taxa.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _abrirMapaEndereco(p.endereco),
                    icon: const Icon(Icons.map_outlined, color: Colors.blue, size: 18),
                    label: const Text('ABRIR MAPA',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: finalizando ? null : () => _aoTocarFinalizarExterna(integracao, p),
                    icon: finalizando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('FINALIZAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mensagemVazia({required IconData icone, required String texto, required Color cor}) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(icone, color: cor, size: 44),
          const SizedBox(height: 10),
          Text(texto, textAlign: TextAlign.center, style: TextStyle(color: cor, fontSize: 14)),
        ],
      ),
    );
  }
}

class _DialogCarregando extends StatelessWidget {
  final String texto;
  const _DialogCarregando({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D1117),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.blue),
            const SizedBox(width: 18),
            Text(texto, style: const TextStyle(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
