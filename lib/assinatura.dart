// Controla se o usuário tem acesso ao app: teste grátis de alguns dias,
// assinatura paga pela Play Store, código de acesso manual, ou liberação
// direta pelo admin. Também tem a tela de "assine agora" (paywall).
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:convert';
import 'database.dart';
import 'codigos.dart';
import 'chat/chat_service.dart';
import 'pagamentos_api.dart';

const String kProdutoIdAssinatura = 'premium_mensal';
const int _diasTrial = 3;

// ─── Enum ─────────────────────────────────────────────────────────────────────

/// Os três estados possíveis de acesso ao app: ainda no teste grátis, com
/// acesso pago/liberado, ou sem acesso (precisa assinar).
enum EstadoAssinatura { emTrial, assinado, expirado }

// ─── Service ──────────────────────────────────────────────────────────────────

class AssinaturaService {
  static final _iap = InAppPurchase.instance;
  static bool _iapDisponivel = false;
  static List<ProductDetails> _produtos = [];

  /// Prepara a compra dentro do app: verifica se a loja (Play Store) está
  /// disponível e busca os detalhes do produto de assinatura (preço etc.).
  /// Chamado uma vez, quando o app abre.
  static Future<void> init() async {
    if (kIsWeb) {
      _iapDisponivel = false;
      return;
    }
    try {
      _iapDisponivel = await _iap.isAvailable();
      if (!_iapDisponivel) return;
      final resp = await _iap.queryProductDetails({kProdutoIdAssinatura});
      _produtos = resp.productDetails;
    } catch (_) {
      _iapDisponivel = false;
    }
  }

  /// Define qual email está logado agora, usado por [verificar] quando
  /// nenhum email é passado explicitamente.
  static void setEmailAtual(String email) => _emailAtual = email;

  /// Se a Play Store está disponível pra comprar a assinatura.
  static bool get iapDisponivel => _iapDisponivel;

  /// Produtos de assinatura carregados da Play Store.
  static List<ProductDetails> get produtos => _produtos;

  /// Descobre o estado atual do acesso do usuário, checando nessa ordem:
  /// liberação manual do admin (local ou pelo Firebase), assinatura paga
  /// pela Play Store, código de acesso ativo, e por fim o teste grátis. Se
  /// nada disso valer, o acesso está expirado.
  static Future<EstadoAssinatura> verificar({String email = ''}) async {
    try {
      // Acesso liberado pelo admin (código local antigo, por aparelho)
      final emailAtual = email.isNotEmpty ? email : _emailAtual;
      if (emailAtual.isNotEmpty) {
        if (await DB.isSubscricaoAtivaParaEmail(emailAtual)) {
          return EstadoAssinatura.assinado;
        }
      }

      // Acesso liberado pelo admin via Firebase (funciona em qualquer aparelho)
      if (await ChatService.isSubscricaoAtivaOnline()) {
        return EstadoAssinatura.assinado;
      }

      // Assinatura via Google Play
      if (await DB.isAssinado()) return EstadoAssinatura.assinado;

      // Assinatura via código de acesso
      final expira = await DB.getSubscricaoExpira();
      if (expira != null && DateTime.now().isBefore(expira)) {
        return EstadoAssinatura.assinado;
      }

      // Assinatura via Pix (só existe na Web, onde não tem Play Store)
      if (kIsWeb) {
        final pix = await PagamentosApi.status();
        if (pix.ativo) return EstadoAssinatura.assinado;
      }

      // Trial gratuito
      final inicio = await DB.getTrialInicio();
      if (inicio == null) {
        await DB.registrarPrimeiroAcesso();
        return EstadoAssinatura.emTrial;
      }

      final dias = DateTime.now().difference(inicio).inDays;
      if (dias < _diasTrial) return EstadoAssinatura.emTrial;

      return EstadoAssinatura.expirado;
    } catch (_) {
      return EstadoAssinatura.emTrial;
    }
  }

  /// Ativa 30 dias de acesso usando um código gerado pelo admin. Se o
  /// usuário já tinha dias de assinatura por código sobrando, os 30 dias
  /// novos somam a partir do vencimento atual (não perde os dias que já
  /// tinha). Retorna false se o código já tiver sido usado antes.
  static Future<bool> ativarCodigo(String codigo) async {
    try {
      if (await DB.isCodigoJaUsado(codigo)) return false;
      final agora = DateTime.now();
      // Se já tem assinatura ativa, estende a partir do vencimento atual
      final expiraAtual = await DB.getSubscricaoExpira();
      final base = (expiraAtual != null && expiraAtual.isAfter(agora)) ? expiraAtual : agora;
      await DB.salvarSubscricaoExpira(base.add(const Duration(days: 30)));
      await DB.marcarCodigoUsado(codigo);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Quantos dias faltam pra assinatura ativada por código vencer.
  static Future<int> diasRestantesSubscricao() async {
    final expira = await DB.getSubscricaoExpira();
    if (expira == null) return 0;
    final diff = expira.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  static String _emailAtual = '';

  /// Quantos dias faltam do teste grátis (0 se já acabou).
  static Future<int> diasRestantesTrial() async {
    try {
      final inicio = await DB.getTrialInicio();
      if (inicio == null) return _diasTrial;
      final usados = DateTime.now().difference(inicio).inDays;
      return (_diasTrial - usados).clamp(0, _diasTrial);
    } catch (_) {
      return 0;
    }
  }

  static StreamSubscription<List<PurchaseDetails>>? _escutaGlobal;
  static final _liberacaoController = StreamController<void>.broadcast();

  /// Começa a escutar as confirmações de compra da Play Store assim que o
  /// app abre, e continua ouvindo durante toda a vida do app (chamado uma
  /// vez em main.dart). Isso garante que a compra seja liberada na hora
  /// mesmo que a confirmação chegue depois que o usuário já saiu da tela
  /// de pagamento (comum com Pix/boleto, que demoram um pouco mais que
  /// cartão, ou se o app for minimizado durante o pagamento). Antes, só a
  /// tela de paywall escutava isso, então uma confirmação que chegasse
  /// fora dela era perdida e o cliente ficava sem o app liberar mesmo já
  /// tendo pago.
  static void iniciarEscutaGlobal() {
    if (kIsWeb || _escutaGlobal != null) return;
    _escutaGlobal = _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        if (p.status == PurchaseStatus.purchased ||
            p.status == PurchaseStatus.restored) {
          try {
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
            await DB.salvarAssinatura();
            _liberacaoController.add(null);
          } catch (_) {
            // Se falhar ao confirmar agora (ex.: sem internet no momento),
            // a compra continua pendente do lado da Play Store e será
            // reprocessada automaticamente na próxima vez que o app
            // conectar com a loja (próxima abertura, ou ao restaurar).
          }
        }
      }
    }, onError: (_) {});
  }

  /// Fica escutando o resultado das compras feitas na Play Store enquanto
  /// a tela de pagamento estiver aberta: quando uma compra é liberada
  /// (processada por [iniciarEscutaGlobal]) chama [onSucesso]; se a compra
  /// der erro (ex.: cancelada), chama [onErro].
  static List<StreamSubscription> ouvirCompras({
    required VoidCallback onSucesso,
    required VoidCallback onErro,
  }) {
    final subLiberacao = _liberacaoController.stream.listen((_) => onSucesso());
    final subErro = _iap.purchaseStream.listen((purchases) {
      for (final p in purchases) {
        if (p.status == PurchaseStatus.error) {
          onErro();
          return;
        }
      }
    });
    return [subLiberacao, subErro];
  }

  /// Abre o fluxo de pagamento da Play Store pro plano mensal.
  static Future<void> assinar() async {
    if (!_iapDisponivel || _produtos.isEmpty) return;
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: _produtos.first),
    );
  }

  /// Restaura uma compra feita antes (ex.: depois de reinstalar o app).
  static Future<void> restaurar() async {
    if (!_iapDisponivel) return;
    await _iap.restorePurchases();
  }
}

// ─── PaywallPage ──────────────────────────────────────────────────────────────

/// Tela de "assine para continuar", mostrada quando o teste grátis acaba
/// (ou quando o usuário quer assinar antes disso). Deixa assinar pela Play
/// Store, digitar um código de acesso, ou restaurar uma compra anterior.
class PaywallPage extends StatefulWidget {
  final VoidCallback onAssinado;
  final bool trialExpirado;

  const PaywallPage({
    super.key,
    required this.onAssinado,
    this.trialExpirado = true,
  });

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  bool _carregando = false;
  String? _erro;
  List<StreamSubscription> _subs = [];

  /// Começa a escutar o resultado da compra assim que a tela abre, pra
  /// saber quando o pagamento foi aprovado (ou deu erro).
  @override
  void initState() {
    super.initState();
    _subs = AssinaturaService.ouvirCompras(
      onSucesso: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Assinatura ativada! Bem-vindo ao Premium!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        widget.onAssinado();
      },
      onErro: () {
        if (!mounted) return;
        setState(() {
          _carregando = false;
          _erro = 'Pagamento cancelado ou falhou. Tente novamente.';
        });
      },
    );
    // Cobre o caso raro de a compra já ter sido confirmada e liberada
    // (pela escuta global) um instante antes dessa tela abrir — assim o
    // usuário não fica preso na tela de pagamento mesmo já tendo pago.
    _verificarJaLiberado();
  }

  Future<void> _verificarJaLiberado() async {
    if (await DB.isAssinado()) {
      if (!mounted) return;
      widget.onAssinado();
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  /// Botão "Assinar agora": abre o pagamento da Play Store.
  Future<void> _assinar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await AssinaturaService.assinar();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Erro ao iniciar pagamento. Tente novamente.';
      });
    }
  }

  /// Botão "Pagar com Pix": gera a cobrança e abre o diálogo com o QR code.
  /// Só aparece onde a Play Store não existe (ver [AssinaturaService.iapDisponivel]).
  Future<void> _pagarComPix() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final pix = await PagamentosApi.criarPix();
      if (!mounted) return;
      setState(() => _carregando = false);
      final pago = await showDialog<bool>(
        context: context,
        builder: (_) => _DialogPix(pix: pix),
      );
      if (pago == true) widget.onAssinado();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e is PagamentosApiException ? e.mensagem : 'Não foi possível gerar o Pix agora. Tente de novo.';
      });
    }
  }

  /// Abre o popup pra digitar um código de acesso e, se for válido, ativa
  /// os 30 dias de acesso.
  Future<void> _inserirCodigo() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.vpn_key_outlined, color: Colors.orange),
          SizedBox(width: 10),
          Text('Inserir código'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Digite o código recebido para liberar 30 dias de acesso.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.orange,
              ),
              decoration: InputDecoration(
                hintText: 'MOTO-XXXXXX-XXX',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 14, letterSpacing: 1),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.orange),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final codigo = controller.text.trim().toUpperCase();
              if (!CodigoAcesso.validar(codigo)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Código inválido. Verifique e tente novamente.'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              final ok = await AssinaturaService.ativarCodigo(codigo);
              if (!mounted) return;
              Navigator.pop(ctx);
              if (ok) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Código ativado! 30 dias de acesso liberados.'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ));
                widget.onAssinado();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Este código já foi utilizado.'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            child: const Text('Ativar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  /// Botão "Restaurar compra anterior".
  Future<void> _restaurar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await AssinaturaService.restaurar();
    } catch (_) {}
    if (mounted) setState(() => _carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 30),

              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.4), width: 2),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'imagens/iconeapp.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Text('🏍️', style: TextStyle(fontSize: 44))),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text('Motoca Premium',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                widget.trialExpirado
                    ? 'Seu teste gratuito de $_diasTrial dias expirou'
                    : 'Assine e aproveite tudo que o app oferece',
                style: const TextStyle(color: Colors.white54, fontSize: 15),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 28),

              // Features
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(children: [
                  _feature(Icons.motorcycle, 'Registre entregas ilimitadas'),
                  _feature(Icons.bar_chart, 'Controle financeiro completo'),
                  _feature(Icons.calendar_month, 'Fechamento mensal'),
                  _feature(Icons.share, 'Envie resumos pelo WhatsApp'),
                  _feature(Icons.lock_open, 'Acesso completo a todos os recursos'),
                ]),
              ),

              const SizedBox(height: 20),

              // Preço
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.withValues(alpha: 0.2),
                      Colors.blue.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.blue, size: 36),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Plano Mensal',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Cancele quando quiser',
                              style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('R\$ 1,99',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue)),
                        Text('/mês',
                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (_erro != null) ...[
                Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_erro!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 12),
              ],

              if (AssinaturaService.iapDisponivel)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _carregando ? null : _assinar,
                    child: _carregando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Assinar agora — R\$ 1,99/mês',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _carregando ? null : _pagarComPix,
                    icon: _carregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.qr_code, size: 20),
                    label: const Text('Pagar com Pix — R\$ 2,00/mês',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),

              const SizedBox(height: 12),

              // Código de acesso
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.orange.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _carregando ? null : _inserirCodigo,
                icon: const Icon(Icons.vpn_key_outlined, color: Colors.orange, size: 18),
                label: const Text('Tenho um código de acesso',
                    style: TextStyle(color: Colors.orange, fontSize: 15)),
              ),

              if (AssinaturaService.iapDisponivel) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _carregando ? null : _restaurar,
                  child: const Text('Restaurar compra anterior',
                      style: TextStyle(color: Colors.white38, fontSize: 14)),
                ),
              ],

              const SizedBox(height: 6),

              Text(
                AssinaturaService.iapDisponivel
                    ? 'Renovação automática mensal. Cancele a qualquer momento pela Play Store.'
                    : 'O Pix não renova sozinho — quando os 30 dias acabarem, é só pagar de novo aqui.',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Uma linha da lista de benefícios do plano (ícone + texto + check).
  Widget _feature(IconData icone, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(texto,
                style: const TextStyle(fontSize: 14, color: Colors.white70)),
          ),
          const Icon(Icons.check_circle_rounded, color: Colors.blue, size: 18),
        ],
      ),
    );
  }
}

// ─── Diálogo do Pix ──────────────────────────────────────────────────────────

/// Mostra o QR code + copia-e-cola do Pix gerado, e fica checando sozinho se
/// o pagamento já caiu (a cada 4s) — fecha e devolve `true` assim que a
/// assinatura for confirmada pelo webhook do backend.
class _DialogPix extends StatefulWidget {
  final PixGerado pix;
  const _DialogPix({required this.pix});

  @override
  State<_DialogPix> createState() => _DialogPixState();
}

class _DialogPixState extends State<_DialogPix> {
  Timer? _timer;
  bool _verificando = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checar());
  }

  Future<void> _checar() async {
    if (_verificando) return;
    _verificando = true;
    try {
      final status = await PagamentosApi.status();
      if (status.ativo && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      // Falha de rede numa checagem não é grave — tenta de novo no próximo tick.
    } finally {
      _verificando = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copiar() {
    Clipboard.setData(ClipboardData(text: widget.pix.copiaCola));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Código Pix copiado!'),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.qr_code, color: Colors.blue),
        SizedBox(width: 10),
        Text('Pagar com Pix'),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'R\$ 2,00 — escaneie o QR code com o app do seu banco ou copie o código. A liberação é automática assim que o pagamento cair.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(widget.pix.qrCodeBase64),
                width: 220,
                height: 220,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _copiar,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  widget.pix.copiaCola,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.blue.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _copiar,
              icon: const Icon(Icons.copy, color: Colors.blue, size: 16),
              label: const Text('Copiar código', style: TextStyle(color: Colors.blue)),
            ),
            const SizedBox(height: 14),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
            ),
            const SizedBox(height: 8),
            const Text('Aguardando pagamento...',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Fechar', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}
