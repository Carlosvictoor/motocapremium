// Aba Perfil: dados do usuário logado (editáveis), veículo, estatísticas
// totais de entregas/km/horas, status da assinatura e central de ajuda.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'database.dart';
import 'assinatura.dart';
import 'auth_service.dart';
import 'termos_page.dart';

class PerfilTab extends StatefulWidget {
  final VoidCallback onLogout;

  const PerfilTab({super.key, required this.onLogout});

  @override
  State<PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends State<PerfilTab> {
  bool _carregando = true;
  EstadoAssinatura? _estado;
  int _diasTrial = 0;
  DateTime? _subscricaoExpira;
  DateTime? _motoboyDesde;
  String? _telefone;
  String? _cpf;
  String? _fotoBase64;
  Map<String, dynamic>? _veiculo;
  int _totalEntregas = 0;
  double _totalKm = 0;
  int _totalMinutosOnline = 0;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  /// Carrega assinatura, dados do perfil e as estatísticas totais (soma de
  /// todo o histórico de dias, não só o dia/mês atual).
  Future<void> _carregarTudo() async {
    final estado = await AssinaturaService.verificar();
    final dias = await AssinaturaService.diasRestantesTrial();
    final expira = await DB.getSubscricaoExpira();
    final motoboyDesde = await DB.getTrialInicio();
    final telefone = await DB.getTelefone();
    final cpf = await DB.getCpf();
    final foto = await DB.getFotoPerfil();
    final veiculo = await DB.getVeiculo();
    final stats = await _calcularEstatisticas();
    if (!mounted) return;
    setState(() {
      _estado = estado;
      _diasTrial = dias;
      _subscricaoExpira = expira;
      _motoboyDesde = motoboyDesde;
      _telefone = telefone;
      _cpf = cpf;
      _fotoBase64 = foto;
      _veiculo = veiculo;
      _totalEntregas = stats.entregas;
      _totalKm = stats.km;
      _totalMinutosOnline = stats.minutos;
      _carregando = false;
    });
  }

  Future<({int entregas, double km, int minutos})> _calcularEstatisticas() async {
    final diasAbertos = await DB.getDias();
    final meses = await DB.getMesesFechados();
    final todosDias = [...diasAbertos, ...meses.expand((m) => m.dias)];
    var entregas = 0;
    var km = 0.0;
    var minutos = 0;
    for (final d in todosDias) {
      entregas += d.totalSaidas;
      km += d.kmRodado;
      minutos += d.tempoOnlineMin;
    }
    return (entregas: entregas, km: km, minutos: minutos);
  }

  /// Escolhe uma foto da galeria, redimensiona pequena e salva em base64.
  Future<void> _trocarFoto() async {
    final XFile? arquivo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 70,
    );
    if (arquivo == null) return;
    final bytes = await arquivo.readAsBytes();
    final base64 = base64Encode(bytes);
    await DB.salvarFotoPerfil(base64);
    if (!mounted) return;
    setState(() => _fotoBase64 = base64);
  }

  Future<void> _editarTelefone() async {
    final valor = await _dialogTexto('Telefone', _telefone ?? '', tipo: TextInputType.phone);
    if (valor == null) return;
    await DB.salvarTelefone(valor);
    if (!mounted) return;
    setState(() => _telefone = valor);
  }

  Future<void> _editarCpf() async {
    final valor = await _dialogTexto('CPF', _cpf ?? '', tipo: TextInputType.number);
    if (valor == null) return;
    await DB.salvarCpf(valor);
    if (!mounted) return;
    setState(() => _cpf = valor);
  }

  /// Diálogo genérico de "editar um texto só" (telefone, CPF).
  Future<String?> _dialogTexto(String titulo, String valorAtual, {TextInputType tipo = TextInputType.text}) async {
    final controller = TextEditingController(text: valorAtual);
    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(titulo),
        content: TextField(
          controller: controller,
          keyboardType: tipo,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1B2435),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    controller.dispose();
    return resultado;
  }

  Future<void> _editarVeiculo() async {
    final descricaoCtrl = TextEditingController(text: _veiculo?['descricao'] as String? ?? '');
    final corCtrl = TextEditingController(text: _veiculo?['cor'] as String? ?? '');
    final anoCtrl = TextEditingController(text: _veiculo?['ano'] as String? ?? '');
    final placaCtrl = TextEditingController(text: _veiculo?['placa'] as String? ?? '');
    var ativo = _veiculo?['ativo'] as bool? ?? true;

    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Meu veículo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _campoVeiculo(descricaoCtrl, 'Marca/modelo', hint: 'Ex: Honda CG 160'),
                const SizedBox(height: 10),
                _campoVeiculo(corCtrl, 'Cor'),
                const SizedBox(height: 10),
                _campoVeiculo(anoCtrl, 'Ano', tipo: TextInputType.number),
                const SizedBox(height: 10),
                _campoVeiculo(placaCtrl, 'Placa'),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Ativo', style: TextStyle(color: Colors.white70)),
                  const Spacer(),
                  Switch(
                    value: ativo,
                    activeColor: Colors.blue,
                    onChanged: (v) => setDialogState(() => ativo = v),
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (salvou != true) return;
    final veiculo = {
      'descricao': descricaoCtrl.text.trim(),
      'cor': corCtrl.text.trim(),
      'ano': anoCtrl.text.trim(),
      'placa': placaCtrl.text.trim(),
      'ativo': ativo,
    };
    descricaoCtrl.dispose();
    corCtrl.dispose();
    anoCtrl.dispose();
    placaCtrl.dispose();
    await DB.salvarVeiculo(veiculo);
    if (!mounted) return;
    setState(() => _veiculo = veiculo);
  }

  Widget _campoVeiculo(TextEditingController ctrl, String label, {String? hint, TextInputType tipo = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: tipo,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFF1B2435),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Future<void> _abrirWhatsappAjuda() async {
    final url = Uri.parse('https://wa.me/5513981865074');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível abrir o WhatsApp.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.blue)));
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text('Perfil', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),

              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 2),
                      ),
                      child: ClipOval(
                        child: _fotoBase64 != null
                            ? Image.memory(base64Decode(_fotoBase64!), fit: BoxFit.cover, width: 110, height: 110)
                            : Image.asset(
                                'imagens/iconeapp.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 52, color: Colors.blue),
                              ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _trocarFoto,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF050816), width: 3),
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AuthService.nomeLogado, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    if (_estado == EstadoAssinatura.assinado) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified, color: Colors.blue, size: 20),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  _motoboyDesde != null ? 'Motoboy desde ${_motoboyDesde!.year}' : 'Motoboy',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    _statBox('$_totalEntregas', 'Total entregas', Colors.orange),
                    Container(width: 1, height: 36, color: Colors.white12),
                    _statBox('${_totalKm.toStringAsFixed(0)} km', 'Km rodados', Colors.green),
                    Container(width: 1, height: 36, color: Colors.white12),
                    _statBox('${(_totalMinutosOnline / 60).floor()} h', 'Horas online', Colors.blue),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _bannerPremium(context),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    _itemEditavel(Icons.person_outline, 'Nome completo', AuthService.nomeLogado),
                    const Divider(color: Colors.white12, height: 1),
                    _itemEditavel(Icons.motorcycle, 'Função', 'Motoboy'),
                    const Divider(color: Colors.white12, height: 1),
                    _itemEditavel(Icons.phone_outlined, 'Telefone',
                        (_telefone == null || _telefone!.isEmpty) ? 'Não informado' : _telefone!,
                        onTap: _editarTelefone),
                    const Divider(color: Colors.white12, height: 1),
                    _itemEditavel(Icons.email_outlined, 'E-mail', AuthService.emailLogado),
                    const Divider(color: Colors.white12, height: 1),
                    _itemEditavel(Icons.badge_outlined, 'CPF',
                        (_cpf == null || _cpf!.isEmpty) ? 'Não informado' : '***.***.***-**',
                        onTap: _editarCpf),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _cardVeiculo(),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    _itemLista(Icons.help_outline, Colors.blue, 'Central de ajuda', _abrirWhatsappAjuda),
                    const Divider(color: Colors.white12, height: 1),
                    _itemLista(Icons.description_outlined, Colors.white70, 'Termos e privacidade',
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermosPage()))),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  minimumSize: const Size(double.infinity, 56),
                ),
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF111827),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Row(children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Sair do sistema?'),
                    ]),
                    content: const Text('Você será redirecionado para a tela de login.', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () async {
                          await DB.limparSessao();
                          widget.onLogout();
                        },
                        child: const Text('Sair', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Sair do sistema', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBox(String valor, String label, Color cor) {
    return Expanded(
      child: Column(
        children: [
          Text(valor, style: TextStyle(color: cor, fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _cardVeiculo() {
    final tem = _veiculo != null && (_veiculo!['descricao'] as String? ?? '').isNotEmpty;
    final ativo = _veiculo?['ativo'] as bool? ?? true;
    final cor = _veiculo?['cor'] as String? ?? '';
    final ano = _veiculo?['ano'] as String? ?? '';
    final placa = _veiculo?['placa'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.two_wheeler, color: Colors.blue, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Meu veículo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            IconButton(
              onPressed: _editarVeiculo,
              icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
              tooltip: 'Editar',
            ),
          ]),
          if (tem) ...[
            const SizedBox(height: 14),
            Text(_veiculo!['descricao'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Row(children: [
              if (cor.isNotEmpty) Expanded(child: _atributoVeiculo(Icons.palette_outlined, 'Cor', cor)),
              if (ano.isNotEmpty) Expanded(child: _atributoVeiculo(Icons.calendar_today_outlined, 'Ano', ano)),
            ]),
            if (cor.isNotEmpty || ano.isNotEmpty) const SizedBox(height: 14),
            Row(children: [
              if (placa.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2435),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(placa.toUpperCase(),
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (ativo ? Colors.green : Colors.grey).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: ativo ? Colors.green : Colors.grey),
                  const SizedBox(width: 6),
                  Text(ativo ? 'Ativo' : 'Inativo',
                      style: TextStyle(fontSize: 12, color: ativo ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
          ] else ...[
            const SizedBox(height: 16),
            Center(
              child: Column(children: [
                Icon(Icons.two_wheeler_outlined, color: Colors.white24, size: 36),
                const SizedBox(height: 8),
                const Text('Nenhum veículo cadastrado ainda.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.blue.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _editarVeiculo,
                  icon: const Icon(Icons.add, color: Colors.blue, size: 18),
                  label: const Text('Cadastrar veículo', style: TextStyle(color: Colors.blue)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _atributoVeiculo(IconData icon, String label, String valor) {
    return Row(children: [
      Icon(icon, color: Colors.white38, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            Text(valor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ]);
  }

  /// Card que muda de cor e texto de acordo com o estado da assinatura:
  /// dourado (ativa), laranja (em teste grátis, com contagem regressiva) ou
  /// vermelho (expirada, com botão pra assinar).
  Widget _bannerPremium(BuildContext context) {
    if (_estado == null) {
      return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    switch (_estado!) {
      case EstadoAssinatura.assinado:
        final expiraTxt = _subscricaoExpira != null ? _formatarData(_subscricaoExpira!) : null;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.amber.withValues(alpha: 0.18), Colors.amber.withValues(alpha: 0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.workspace_premium, color: Colors.amber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Plano Premium', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(expiraTxt != null ? 'Ativo até $expiraTxt' : 'Ativo', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ]),
        );

      case EstadoAssinatura.emTrial:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.timer_outlined, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _diasTrial == 1 ? 'Último dia de teste gratuito!' : 'Teste gratuito: $_diasTrial dias restantes',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Text('Assine para continuar após o período', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaywallPage(
                    trialExpirado: false,
                    onAssinado: () {
                      Navigator.pop(context);
                      _carregarTudo();
                    },
                  ),
                ),
              ),
              child: const Text('Assinar', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
          ]),
        );

      case EstadoAssinatura.expirado:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.lock_outline, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Teste expirado', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('Assine para continuar usando o app', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaywallPage(
                    trialExpirado: true,
                    onAssinado: () {
                      Navigator.pop(context);
                      _carregarTudo();
                    },
                  ),
                ),
              ),
              child: const Text('Assinar', style: TextStyle(fontSize: 14)),
            ),
          ]),
        );
    }
  }

  /// Uma linha da lista de dados do perfil: ícone, traço divisório, e o
  /// rótulo/valor empilhados (rótulo pequeno em cima, valor em negrito
  /// embaixo). Se tiver [onTap], mostra uma setinha e abre o diálogo de
  /// edição.
  Widget _itemEditavel(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 22),
            const SizedBox(width: 16),
            Container(width: 1, height: 38, color: Colors.white24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  /// Uma linha da lista de ações (Central de ajuda, Termos etc.).
  Widget _itemLista(IconData icon, Color cor, String texto, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Icon(icon, color: cor, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 15))),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
        ]),
      ),
    );
  }
}
