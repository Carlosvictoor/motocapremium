// O "cérebro" do app depois do login: guarda os dados do dia (saídas,
// KM, tempo online), dos meses em aberto (dias e gastos) e monta a barra
// de abas (Home, Pedidos, Financeiro, Resumo, Perfil) trocando de tela sem
// perder esses dados.
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'models.dart';
import 'database.dart';
import 'localizacao_api.dart';
import 'motoboy_zerar_dia_api.dart';
import 'utils.dart';
import 'pedidos/pedidos_tab.dart';
import 'login_page.dart';
import 'home_tab.dart';
import 'financeiro_tab.dart';
import 'resumo_tab.dart';
import 'perfil_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tabIndex = 0;

  List<Saida> saidas = [];
  List<DiaRegistro> dias = [];
  List<Gasto> gastos = [];
  List<MesFechado> mesesFechados = [];
  double _kmTotal = 0;

  /// true quando [_carregarDados] esgotou as tentativas e desistiu — nesse
  /// caso NÃO dá pra confiar que as listas acima (vazias) refletem a
  /// realidade, então a tela mostra um aviso explícito em vez de deixar o
  /// usuário achar que os dados salvos sumiram.
  bool _erroCarregarDados = false;

  // odômetro automático (antes vivia na tela de Mapa, agora roda sempre)
  ({double lat, double lon})? _posOdometroAnterior;
  StreamSubscription<Position>? _odometroSub;
  double _kmBuffer = 0;
  String? _statusOdometro;
  DateTime? _ultimaLeituraOdometro;

  // Localização pro painel do restaurante (Fase 13) — reaproveita o mesmo
  // GPS do odômetro acima, só decide com que frequência salva no
  // Firestore: sempre que tem pedido ativo, no máximo 1x a cada 3 minutos
  // sem nenhum (ver PedidosTab.onPedidoAtivoMudou).
  bool _temPedidoAtivo = false;
  DateTime? _ultimoSalvamentoLocalizacao;

  // KM manual (botão Iniciar/Finalizar): guarda o KM inicial digitado pelo
  // motoboy enquanto a contagem estiver em andamento (null = nenhuma
  // contagem aberta). Independente do odômetro automático por GPS acima.
  double? _kmManualInicio;

  // tempo online: desde a primeira vez que abriu o app hoje (ou desde o
  // último "Zerar o dia"), roda no relógio mesmo com a tela apagada.
  DateTime? _onlineInicio;
  Duration _tempoOnline = Duration.zero;
  Timer? _tempoOnlineTimer;

  /// Soma o valor de todas as saídas registradas hoje (ainda não zeradas).
  double get _totalDia => saidas.fold(0.0, (s, r) => s + r.valorTotal);

  @override
  void initState() {
    super.initState();
    _carregarDados();
    _iniciarTempoOnline();
    _pedirPermissaoLocalizacaoEIniciarOdometro();
  }

  /// Carrega do banco local o horário em que o "Tempo online" começou a
  /// contar (se já tiver começado hoje) e liga um cronômetro que atualiza a
  /// tela a cada 30 segundos enquanto o relógio estiver rodando.
  Future<void> _iniciarTempoOnline() async {
    // Não cria início automaticamente aqui — o relógio só começa a contar
    // quando a primeira saída do dia é registrada (ver registrarSaida).
    final inicio = await DB.getOnlineInicio();
    if (!mounted) return;
    setState(() {
      _onlineInicio = inicio;
      _tempoOnline = inicio == null ? Duration.zero : DateTime.now().difference(inicio);
    });
    _tempoOnlineTimer?.cancel();
    _tempoOnlineTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _onlineInicio != null) {
        setState(() => _tempoOnline = DateTime.now().difference(_onlineInicio!));
      }
    });
  }

  /// Pede a permissão de localização (se ainda não tiver) e, se conseguir,
  /// liga o odômetro que conta o KM rodado. Se a localização estiver
  /// desativada ou a permissão for negada, guarda um aviso em
  /// [_statusOdometro] pra mostrar na tela em vez de falhar em silêncio.
  Future<void> _pedirPermissaoLocalizacaoEIniciarOdometro() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _statusOdometro = 'Localização desativada no aparelho');
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        if (mounted) setState(() => _statusOdometro = 'Permissão de localização negada');
        return;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _statusOdometro = 'Permissão de localização bloqueada — ative nas configurações do app');
      return;
    }
    _iniciarOdometro();
  }

  @override
  void dispose() {
    _odometroSub?.cancel();
    _tempoOnlineTimer?.cancel();
    if (_kmBuffer > 0) {
      final km = _kmBuffer;
      _kmBuffer = 0;
      DB.adicionarKm(km);
    }
    super.dispose();
  }

  /// Liga o rastreamento de localização em segundo plano (com notificação
  /// permanente no Android) e, a cada posição nova, calcula a distância
  /// desde a última leitura pra ir somando o KM rodado no dia.
  void _iniciarOdometro() {
    _odometroSub?.cancel();
    final LocationSettings settings = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Motoca Premium',
              notificationText: 'Rastreando KM rodado em segundo plano',
              enableWakeLock: true,
              setOngoing: true,
              notificationChannelName: 'Rastreamento de KM',
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
          );

    if (mounted) setState(() => _statusOdometro = null);

    _odometroSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      final atual = (lat: pos.latitude, lon: pos.longitude);
      if (mounted) setState(() => _ultimaLeituraOdometro = DateTime.now());

      final agora = DateTime.now();
      final deveSalvarLocalizacao = _temPedidoAtivo ||
          _ultimoSalvamentoLocalizacao == null ||
          agora.difference(_ultimoSalvamentoLocalizacao!) >= const Duration(minutes: 3);
      if (deveSalvarLocalizacao) {
        _ultimoSalvamentoLocalizacao = agora;
        LocalizacaoApi.salvar(atual.lat, atual.lon);
      }

      if (_posOdometroAnterior != null) {
        final distM = Geolocator.distanceBetween(
          _posOdometroAnterior!.lat, _posOdometroAnterior!.lon,
          atual.lat, atual.lon,
        );
        // Ignora saltos absurdos entre duas leituras (>500m), sinal de
        // erro/reaquisição de GPS, não de deslocamento real.
        if (distM <= 500) {
          _kmBuffer += distM / 1000.0;
          if (_kmBuffer >= 0.1) { // salva no banco a cada 100m acumulados
            final km = _kmBuffer;
            _kmBuffer = 0;
            DB.adicionarKm(km).then((_) {
              if (mounted) setState(() => _kmTotal += km);
            });
          }
        }
      }
      _posOdometroAnterior = atual;
    }, onError: (e) {
      if (mounted) setState(() => _statusOdometro = 'Erro no GPS: $e');
    });
  }

  /// Começa a contagem manual de KM: guarda o valor que o motoboy leu no
  /// odômetro da moto (botão "Iniciar" na Home).
  Future<void> iniciarKmManual(double kmInicial) async {
    await DB.salvarKmManualInicio(kmInicial);
    if (mounted) setState(() => _kmManualInicio = kmInicial);
  }

  /// Termina a contagem manual de KM: calcula a diferença entre o KM final
  /// digitado e o KM inicial salvo, e soma esse trecho ao KM rodado hoje
  /// (mesmo total usado pelo odômetro automático por GPS).
  Future<void> finalizarKmManual(double kmFinal) async {
    final kmInicial = _kmManualInicio;
    if (kmInicial == null) return;
    final percorrido = kmFinal - kmInicial;
    if (percorrido > 0) await DB.adicionarKm(percorrido);
    await DB.zerarKmManualInicio();
    if (!mounted) return;
    setState(() {
      if (percorrido > 0) _kmTotal += percorrido;
      _kmManualInicio = null;
    });
  }

  /// Carrega do banco local tudo que a tela precisa mostrar: saídas do dia,
  /// dias e gastos ainda em aberto, meses já fechados e o KM total. Também
  /// aproveita pra fechar automaticamente meses antigos que ficaram abertos.
  ///
  /// Na Web, logo após o login/refresh o Firestore às vezes rejeita a
  /// primeira leitura (permission-denied transitório, porque o token do
  /// Firebase Auth ainda não propagou por completo pro SDK do Firestore),
  /// mesmo com [ChatService.meuUid] já preenchido. Sem retry, esse erro
  /// passageiro era engolido silenciosamente e a tela ficava vazia pro
  /// resto da sessão — dando a impressão de que os dados salvos tinham
  /// sumido, quando na verdade continuavam intactos no Firestore. Por
  /// isso tenta de novo algumas vezes antes de desistir.
  Future<void> _carregarDados() async {
    const tentativas = 4;
    for (var tentativa = 1; tentativa <= tentativas; tentativa++) {
      try {
        final s = await DB.getSaidasAtivas();
        var d = await DB.getDias();
        var g = await DB.getGastos();
        var m = await DB.getMesesFechados();
        final km = await DB.getKmTotal();
        final kmManualInicio = await DB.getKmManualInicio();

        // Fecha automaticamente meses anteriores que ainda estejam abertos
        await _autoFecharMesesAntigos(d, g);
        // Recarrega após possível fechamento automático
        d = await DB.getDias();
        g = await DB.getGastos();
        m = await DB.getMesesFechados();

        if (!mounted) return;
        setState(() {
          saidas = s;
          dias = d;
          gastos = g;
          mesesFechados = m;
          _kmTotal = km;
          _kmManualInicio = kmManualInicio;
          _erroCarregarDados = false;
        });
        return;
      } catch (_) {
        if (tentativa == tentativas) {
          // Esgotou as tentativas: NÃO deixa a tela passar a falsa
          // impressão de "sem dados" — avisa e oferece botão de tentar de
          // novo (ver banner no build()).
          if (mounted) setState(() => _erroCarregarDados = true);
          return;
        }
        await Future.delayed(Duration(milliseconds: 400 * tentativa));
      }
    }
  }

  /// Se o usuário deixou dias/gastos de meses anteriores sem fechar (ex.:
  /// esqueceu de fechar o mês passado), fecha eles automaticamente aqui,
  /// em ordem cronológica, pra não misturar meses diferentes no histórico
  /// em aberto.
  Future<void> _autoFecharMesesAntigos(List<DiaRegistro> diasAbertos, List<Gasto> gastosAbertos) async {
    final agora = DateTime.now();
    // Encontra meses/anos distintos com dados abertos que NÃO sejam o mês atual
    final mesesAntigos = <String, (int, int)>{};
    for (final dia in diasAbertos) {
      if (dia.data.year < agora.year ||
          (dia.data.year == agora.year && dia.data.month < agora.month)) {
        final key = '${dia.data.year}-${dia.data.month}';
        mesesAntigos[key] = (dia.data.month, dia.data.year);
      }
    }
    for (final g in gastosAbertos) {
      if (g.data.year < agora.year ||
          (g.data.year == agora.year && g.data.month < agora.month)) {
        final key = '${g.data.year}-${g.data.month}';
        mesesAntigos[key] = (g.data.month, g.data.year);
      }
    }
    if (mesesAntigos.isEmpty) return;

    // Fecha cada mês antigo em ordem cronológica
    final ordenados = mesesAntigos.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in ordenados) {
      final (mes, ano) = entry.value;
      final id = await DB.inserirMesFechado(mes, ano);
      if (id >= 0) await DB.vincularAoMesPorMesAno(id, mes, ano);
    }
  }

  /// Registra uma saída nova (entrega) com os valores digitados na Home.
  /// Se essa for a primeira saída desde o último "Zerar o dia", também
  /// liga o relógio do "Tempo online".
  Future<void> registrarSaida({
    required String paga,
    required String comanda,
    required String taxa,
    required String gorjeta,
  }) async {
    if (paga.isEmpty && comanda.isEmpty && taxa.isEmpty && gorjeta.isEmpty) {
      return;
    }

    final novaSaida = Saida(
      hora: DateTime.now(),
      paga: paga.isNotEmpty ? paga : null,
      taxa: taxa.isNotEmpty ? taxa : null,
      gorjeta: gorjeta.isNotEmpty ? gorjeta : null,
      comandas: comanda.isNotEmpty ? comanda : null,
    );

    final dbId = await DB.inserirSaidaAtiva(novaSaida);

    // Primeira saída do dia (desde o último "Zerar o dia") liga o relógio
    // do "Tempo online".
    DateTime? novoInicio;
    if (_onlineInicio == null) {
      novoInicio = DateTime.now();
      await DB.salvarOnlineInicio(novoInicio);
    }

    setState(() {
      saidas.insert(
        0,
        Saida(
          dbId: dbId > 0 ? dbId : null,
          hora: novaSaida.hora,
          paga: novaSaida.paga,
          taxa: novaSaida.taxa,
          gorjeta: novaSaida.gorjeta,
          comandas: novaSaida.comandas,
        ),
      );
      if (novoInicio != null) {
        _onlineInicio = novoInicio;
        _tempoOnline = Duration.zero;
      }
    });
  }

  /// Remove uma saída registrada hoje (antes de zerar o dia).
  Future<void> deletarSaida(Saida s) async {
    if (s.dbId != null) await DB.deletarSaidaAtiva(s.dbId!);
    setState(() => saidas.remove(s));
  }

  /// Corrige a comanda e/ou a taxa de uma saída já registrada hoje (caso o
  /// motoboy erre ao digitar) — não mexe em Paga/Gorjeta.
  Future<void> editarSaida(Saida s, {required String comanda, required String taxa}) async {
    final novaComanda = comanda.trim().isNotEmpty ? comanda.trim() : null;
    final novaTaxa = taxa.trim().isNotEmpty ? taxa.trim() : null;

    if (s.dbId != null) {
      await DB.atualizarSaidaAtiva(s.dbId!, comanda: novaComanda, taxa: novaTaxa);
    }

    setState(() {
      final i = saidas.indexOf(s);
      if (i != -1) {
        saidas[i] = Saida(
          dbId: s.dbId,
          hora: s.hora,
          paga: s.paga,
          gorjeta: s.gorjeta,
          taxa: novaTaxa,
          comandas: novaComanda,
        );
      }
    });
  }

  /// Pergunta se quer mesmo zerar o dia; se confirmar, salva as saídas de
  /// hoje (junto com o KM e o tempo online do dia) no histórico do
  /// Financeiro e limpa tudo pra começar o dia seguinte do zero.
  Future<void> _zerarODia(BuildContext ctx) async {
    if (saidas.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Nenhum registro para salvar.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final confirmado = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.power_settings_new, color: Colors.red),
          SizedBox(width: 10),
          Text('Zerar o dia?'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Resumo do dia
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.motorcycle, color: Colors.blue, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          contarSaidas(saidas).toString(),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                        const Text('saídas', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 60, color: Colors.white12),
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.attach_money, color: Colors.green, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          'R\$ ${_totalDia.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                          textAlign: TextAlign.center,
                        ),
                        const Text('total ganho', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'O dia será salvo no Financeiro e o registro zerado.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Zerar',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    final dia = DiaRegistro(
      data: DateTime.now(),
      saidas: List.from(saidas),
      kmRodado: _kmTotal,
      tempoOnlineMin: _tempoOnline.inMinutes,
    );
    await DB.salvarDia(dia);
    await DB.limparSaidasAtivas();
    // Avisa o backend (best-effort) pra sincronizar o corte de "hoje" do
    // relatório do painel do restaurante (Fase 12) com esse exato momento.
    unawaited(MotoboyZerarDiaApi.avisar());

    // Zera KM e tempo online do dia — o histórico já foi salvo no DiaRegistro acima.
    // O relógio do "Tempo online" só volta a contar na próxima saída registrada.
    await DB.zerarKmTotal();
    await DB.zerarOnlineInicio();
    await DB.zerarKmManualInicio();

    setState(() {
      dias.insert(0, dia);
      saidas.clear();
      _kmTotal = 0;
      _onlineInicio = null;
      _tempoOnline = Duration.zero;
      _kmManualInicio = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Dia salvo no Financeiro!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Monta um resumo do dia em texto e abre o WhatsApp com a mensagem
  /// pronta pra enviar (pro chefe, pra si mesmo, etc.).
  Future<void> _enviarResumo(BuildContext ctx) async {
    if (saidas.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Nenhum registro para enviar.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final dataRef = saidas.last.hora;
    final dataStr =
        '${dataRef.day.toString().padLeft(2, '0')}/${dataRef.month.toString().padLeft(2, '0')}/${dataRef.year}';

    final msg = StringBuffer();
    msg.writeln('🏍️ *Motoca Premium — Resumo do Dia*');
    msg.writeln('📅 $dataStr');
    msg.writeln('━━━━━━━━━━━━━━━━━━━━');
    msg.writeln('');

    final lista = saidas.reversed.toList();
    for (int i = 0; i < lista.length; i++) {
      final s = lista[i];
      msg.writeln('*Saída ${i + 1}* (${s.horaStr})');
      if (s.paga != null) msg.writeln('  💳 Paga: R\$ ${s.paga}');
      if (s.taxa != null) msg.writeln('  💰 Taxa: R\$ ${s.taxa}');
      if (s.gorjeta != null) msg.writeln('  🎁 Gorjeta: R\$ ${s.gorjeta}');
      if (s.comandas != null) msg.writeln('  🧾 Comandas: ${s.comandas}');
      if (s.valorTotal > 0) {
        msg.writeln('  💵 _Total: R\$ ${s.valorTotal.toStringAsFixed(2)}_');
      }
      if (i < lista.length - 1) msg.writeln('');
    }

    msg.writeln('');
    msg.writeln('━━━━━━━━━━━━━━━━━━━━');
    msg.writeln('🚗 *Total de saídas:* ${contarSaidas(saidas)}');
    msg.writeln('💵 *Total ganho:* R\$ ${_totalDia.toStringAsFixed(2)}');
    msg.writeln('━━━━━━━━━━━━━━━━━━━━');
    msg.writeln('_Enviado via Motoca Premium_ 🚀');

    final texto = Uri.encodeComponent(msg.toString());
    final url = Uri.parse('https://wa.me/?text=$texto');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Não foi possível abrir o WhatsApp.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  /// Adiciona um gasto novo (combustível, manutenção etc.) na aba Financeiro.
  Future<void> adicionarGasto(Gasto gasto) async {
    await DB.inserirGasto(gasto);
    setState(() => gastos.insert(0, gasto));
  }

  /// Remove um gasto registrado.
  Future<void> deletarGasto(Gasto gasto) async {
    if (gasto.dbId != null) await DB.deletarGasto(gasto.dbId!);
    setState(() => gastos.remove(gasto));
  }

  /// Remove um dia do histórico do Financeiro.
  Future<void> deletarDia(DiaRegistro dia) async {
    if (dia.dbId != null) await DB.deletarDia(dia.dbId!);
    setState(() => dias.remove(dia));
  }

  /// Remove um mês fechado do histórico.
  Future<void> deletarMes(MesFechado mes) async {
    if (mes.dbId != null) await DB.deletarMesFechado(mes.dbId!);
    setState(() => mesesFechados.remove(mes));
  }

  /// Pergunta se quer mesmo fechar o mês; se confirmar, arquiva todos os
  /// dias e gastos do mês atual num "MesFechado" e limpa o histórico em
  /// aberto pra começar o mês seguinte do zero.
  Future<void> fecharMes(BuildContext ctx) async {
    if (dias.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Nenhum dia registrado para fechar.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final agora = DateTime.now();
    final mesLabel = labelMes(agora.month, agora.year);
    final totalGanho = dias.fold(0.0, (s, d) => s + d.total);
    final totalGastos = gastos.fold(0.0, (s, g) => s + g.valor);

    final confirmado = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.calendar_month, color: Colors.purple),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Fechar $mesLabel?',
                  style: const TextStyle(fontSize: 20))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${dias.length} dia(s) registrado(s)',
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.trending_up, color: Colors.green, size: 18),
              const SizedBox(width: 6),
              Text('Total ganho: R\$ ${totalGanho.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.green, fontSize: 15)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.trending_down, color: Colors.red, size: 18),
              const SizedBox(width: 6),
              Text('Total gastos: R\$ ${totalGastos.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.red, fontSize: 15)),
            ]),
            const SizedBox(height: 12),
            const Text(
                'O mês será salvo e o histórico zerado.',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Fechar Mês',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    final id = await DB.inserirMesFechado(agora.month, agora.year);
    if (id >= 0) await DB.vincularAoMes(id);

    setState(() {
      mesesFechados.insert(
        0,
        MesFechado(
          mes: agora.month,
          ano: agora.year,
          dias: List.from(dias),
          gastos: List.from(gastos),
        ),
      );
      dias.clear();
      gastos.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('$mesLabel fechado com sucesso!'),
        backgroundColor: Colors.purple,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeTab(
        saidas: saidas,
        totalDia: _totalDia,
        kmHoje: _kmTotal,
        tempoOnline: _tempoOnline,
        statusOdometro: _statusOdometro,
        ultimaLeituraOdometro: _ultimaLeituraOdometro,
        kmManualInicio: _kmManualInicio,
        onIniciarKmManual: iniciarKmManual,
        onFinalizarKmManual: finalizarKmManual,
        onRegistrar: registrarSaida,
        onZerar: () => _zerarODia(context),
        onEnviarResumo: () => _enviarResumo(context),
        onVerFinanceiro: () => setState(() => _tabIndex = 2),
        onDeletarSaida: deletarSaida,
        onEditarSaida: editarSaida,
      ),
      PedidosTab(
        onEntregaFinalizada: ({required String taxa, required String referencia}) {
          registrarSaida(paga: '', comanda: referencia, taxa: taxa, gorjeta: '');
        },
        onPedidoAtivoMudou: (temAtivo) => _temPedidoAtivo = temAtivo,
      ),
      FinanceiroTab(
        dias: dias,
        gastos: gastos,
        mesesFechados: mesesFechados,
        saidaTotal: _totalDia,
        onAdicionarGasto: adicionarGasto,
        onDeletarGasto: deletarGasto,
        onFecharMes: () => fecharMes(context),
        onDeletarDia: deletarDia,
        onDeletarMes: deletarMes,
      ),
      ResumoTab(
        dias: dias,
        saidas: saidas,
        totalDia: _totalDia,
        gastos: gastos,
        kmTotal: _kmTotal,
        tempoOnline: _tempoOnline,
      ),
      PerfilTab(
        onLogout: () => Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        ),
      ),
    ];

    return Scaffold(
      body: Column(
        children: [
          if (_erroCarregarDados) _bannerErroCarregamento(),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: tabs,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// Aviso fixo no topo quando [_carregarDados] não conseguiu ler os dados
  /// salvos mesmo depois de várias tentativas — deixa claro que é uma
  /// falha de conexão/carregamento, não que os dados foram apagados, e dá
  /// um jeito de tentar de novo sem precisar dar F5 na página.
  Widget _bannerErroCarregamento() {
    return Material(
      color: Colors.red.shade900,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Não deu pra carregar seus dados salvos agora. Eles continuam seguros — tenta de novo.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: _carregarDados,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Tentar de novo', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Monta a barra de abas fixa no rodapé (Home, Feed, Financeiro, Resumo,
  /// Perfil), destacando qual está selecionada.
  Widget _buildBottomNav() {
    const bg = Color(0xFF0D1117);
    const selectedColor = Colors.blue;
    const unselectedColor = Colors.white38;

    final items = [
      {'label': 'Home', 'icon': Icons.home_outlined, 'activeIcon': Icons.home},
      {'label': 'Pedidos', 'icon': Icons.local_shipping_outlined, 'activeIcon': Icons.local_shipping},
      {'label': 'Financeiro', 'icon': Icons.bar_chart_outlined, 'activeIcon': Icons.bar_chart},
      {'label': 'Resumo', 'icon': Icons.description_outlined, 'activeIcon': Icons.description},
      {'label': 'Perfil', 'icon': Icons.person_outline, 'activeIcon': Icons.person},
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final selected = _tabIndex == i;
              final label = items[i]['label'] as String;
              final icon = items[i]['icon'] as IconData;
              final activeIcon = items[i]['activeIcon'] as IconData;
              final isFinanceiro = i == 2;

              return GestureDetector(
                onTap: () => setState(() => _tabIndex = i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    isFinanceiro && selected
                        ? Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: selectedColor.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(activeIcon, color: selectedColor, size: 24),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              selected ? activeIcon : icon,
                              color: selected ? selectedColor : unselectedColor,
                              size: 24,
                            ),
                          ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? selectedColor : unselectedColor,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
