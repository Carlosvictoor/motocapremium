// Tela do painel Admin pra cadastrar um motoboy num restaurante: digita o
// Merchant ID que a Saipos gerou pra aquele entregador (tela "Entregadores"
// > "Usar serviço de entrega" > Motoca Premium), o app gera Client ID/Secret
// e mostra pra copiar e colar de volta na Saipos. Ver contexto completo em
// backend/src/routes/adminLojas.ts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'admin.dart';
import 'chat/chat_service.dart';
import 'widgets/selecionar_motoboy.dart';

class AdminMotoboysPage extends StatefulWidget {
  const AdminMotoboysPage({super.key});

  @override
  State<AdminMotoboysPage> createState() => _AdminMotoboysPageState();
}

class _AdminMotoboysPageState extends State<AdminMotoboysPage> {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _motoboys = [];
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _integracoes = [];

  final _nomeRestauranteController = TextEditingController();
  final _merchantIdController = TextEditingController();
  String? _motoboySelecionadoUid;
  String? _restauranteSelecionadoUid;
  TextEditingController? _motoboyFieldController;
  bool _gerando = false;

  final _nomeIntegracaoController = TextEditingController();
  final _urlIntegracaoController = TextEditingController();
  String? _motoboySelecionadoIntegracaoUid;
  String? _restauranteSelecionadoIntegracaoUid;
  TextEditingController? _motoboyIntegracaoFieldController;
  bool _salvandoIntegracao = false;

  List<OpcaoMotoboy> get _opcoesMotoboys =>
      _motoboysReais.map((u) => OpcaoMotoboy(uid: u['uid'] as String, nome: u['nome'] as String, email: u['email'] as String)).toList();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeRestauranteController.dispose();
    _merchantIdController.dispose();
    _nomeIntegracaoController.dispose();
    _urlIntegracaoController.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
        'X-Admin-Key': kAdminApiKey,
        'Content-Type': 'application/json',
      };

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final motoboys = await ChatService.getTodosUsuariosAdmin();
      final resp = await http
          .get(Uri.parse('$_baseUrl/admin/lojas'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      final respIntegracoes = await http
          .get(Uri.parse('$_baseUrl/admin/integracoes'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        throw Exception('Backend retornou ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final registros = (data['registros'] as List).cast<Map<String, dynamic>>();

      final integracoes = respIntegracoes.statusCode == 200
          ? ((jsonDecode(respIntegracoes.body) as Map<String, dynamic>)['registros'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _motoboys = motoboys;
        _registros = registros;
        _integracoes = integracoes;
        _carregando = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _erro = 'Sem conexão com a internet.';
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não consegui carregar: $e';
        _carregando = false;
      });
    }
  }

  /// Nome do motoboy a partir do uid (pra mostrar em vez do uid cru na lista).
  String _nomeDoMotoboy(String uid) {
    final m = _motoboys.where((u) => u['uid'] == uid).toList();
    if (m.isEmpty) return uid;
    final nome = m.first['nome'] as String?;
    return (nome == null || nome.isEmpty) ? uid : nome;
  }

  /// Só contas de motoboy de verdade (exclui contas de restaurante, que
  /// também vêm de `getTodosUsuariosAdmin()` mas não fazem entrega).
  List<Map<String, dynamic>> get _motoboysReais =>
      _motoboys.where((u) => u['tipo'] != 'restaurante').toList();

  /// Contas de restaurante cadastradas — pra escolher quem é o dono de uma
  /// loja/integração ao cadastrar (ver Fase 11.1).
  List<Map<String, dynamic>> get _restaurantes =>
      _motoboys.where((u) => u['tipo'] == 'restaurante').toList();

  /// Cadastra uma integração externa de leitura nova (outro sistema de
  /// delivery, fora a Saipos) pra um motoboy.
  Future<void> _salvarIntegracao() async {
    final nome = _nomeIntegracaoController.text.trim();
    final url = _urlIntegracaoController.text.trim();
    final motoboyUid = _motoboySelecionadoIntegracaoUid;

    if (nome.isEmpty || url.isEmpty || motoboyUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Preenche o motoboy, o nome do sistema e a URL.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _salvandoIntegracao = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/admin/integracoes'),
            headers: _headers,
            body: jsonEncode({
              'motoboyUid': motoboyUid,
              'nome': nome,
              'url': url,
              'restauranteUid': _restauranteSelecionadoIntegracaoUid,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 201) {
        throw Exception('Backend retornou ${resp.statusCode}');
      }

      _nomeIntegracaoController.clear();
      _urlIntegracaoController.clear();
      _motoboyIntegracaoFieldController?.clear();
      setState(() {
        _motoboySelecionadoIntegracaoUid = null;
        _restauranteSelecionadoIntegracaoUid = null;
      });
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Integração cadastrada!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _salvandoIntegracao = false);
    }
  }

  Future<void> _removerIntegracao(int id) async {
    try {
      await http.delete(Uri.parse('$_baseUrl/admin/integracoes/$id'), headers: _headers).timeout(const Duration(seconds: 15));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao remover: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _gerarCredenciais() async {
    final nomeRestaurante = _nomeRestauranteController.text.trim();
    final merchantId = _merchantIdController.text.trim();
    final motoboyUid = _motoboySelecionadoUid;

    if (nomeRestaurante.isEmpty || merchantId.isEmpty || motoboyUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Preenche o motoboy, o nome do restaurante e o Merchant ID.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _gerando = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/admin/lojas'),
            headers: _headers,
            body: jsonEncode({
              'merchantId': merchantId,
              'motoboyUid': motoboyUid,
              'nomeRestaurante': nomeRestaurante,
              'restauranteUid': _restauranteSelecionadoUid,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 409) {
        throw Exception('Esse Merchant ID já está cadastrado.');
      }
      if (resp.statusCode != 201) {
        throw Exception('Backend retornou ${resp.statusCode}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      await _mostrarCredenciaisGeradas(
        clientId: data['clientId'] as String,
        clientSecret: data['clientSecret'] as String,
      );

      _nomeRestauranteController.clear();
      _merchantIdController.clear();
      _motoboyFieldController?.clear();
      setState(() {
        _motoboySelecionadoUid = null;
        _restauranteSelecionadoUid = null;
      });
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  Future<void> _mostrarCredenciaisGeradas({required String clientId, required String clientSecret}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.vpn_key, color: Colors.green),
          SizedBox(width: 10),
          Text('Credenciais geradas!'),
        ]),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _campoCopiavel(String rotulo, String valor) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: valor));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$rotulo copiado!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
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
            Text(rotulo, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(valor,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.copy, color: Colors.white38, size: 16),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _remover(Map<String, dynamic> registro) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remover motoboy?'),
        content: Text(
          'Remover o vínculo de ${_nomeDoMotoboy(registro['motoboyUid'] as String)} com ${registro['nomeRestaurante']}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await http.delete(Uri.parse('$_baseUrl/admin/lojas/${registro['id']}'), headers: _headers).timeout(const Duration(seconds: 15));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao remover: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Agrupa os registros por nome de restaurante, na ordem que já vem do
  /// backend (que já ordena por nome).
  Map<String, List<Map<String, dynamic>>> get _registrosPorRestaurante {
    final mapa = <String, List<Map<String, dynamic>>>{};
    for (final r in _registros) {
      final nome = r['nomeRestaurante'] as String;
      mapa.putIfAbsent(nome, () => []).add(r);
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        title: const Text('Adicionar motoboy'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _erro != null
              ? Center(child: Text(_erro!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _formularioNovo(),
                      const SizedBox(height: 24),
                      const Text('Motoboys cadastrados',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_registros.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
                          child: const Center(
                            child: Text('Nenhum motoboy vinculado a um restaurante ainda.',
                                style: TextStyle(color: Colors.white38)),
                          ),
                        )
                      else
                        ..._registrosPorRestaurante.entries.map(_grupoRestaurante),

                      const SizedBox(height: 32),
                      const Text('Outras integrações (leitura)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text(
                        'Outros sistemas de delivery (fora a Saipos) que um motoboy quer ver os pedidos dentro do app — só leitura, sem aceitar/finalizar por aqui.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      _formularioIntegracao(),
                      const SizedBox(height: 16),
                      if (_integracoes.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
                          child: const Center(
                            child: Text('Nenhuma integração externa cadastrada ainda.',
                                style: TextStyle(color: Colors.white38)),
                          ),
                        )
                      else
                        ..._integracoes.map(_itemIntegracao),
                    ],
                  ),
                ),
    );
  }

  Widget _formularioIntegracao() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nova integração', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          const Text('Motoboy', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          SelecionarMotoboy(
            opcoes: _opcoesMotoboys,
            onSelecionado: (v) => setState(() => _motoboySelecionadoIntegracaoUid = v),
            onControllerReady: (c) => _motoboyIntegracaoFieldController = c,
          ),
          const SizedBox(height: 14),

          const Text('Restaurante (opcional)', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0xFF1B2435), borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                dropdownColor: const Color(0xFF1B2435),
                value: _restauranteSelecionadoIntegracaoUid,
                hint: const Text('Nenhum', style: TextStyle(color: Colors.white38)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
                  ..._restaurantes.map((u) => DropdownMenuItem<String?>(
                        value: u['uid'] as String,
                        child: Text('${u['nome']} (${u['email']})', overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _restauranteSelecionadoIntegracaoUid = v),
              ),
            ),
          ),
          const SizedBox(height: 14),

          const Text('Nome do sistema', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _nomeIntegracaoController,
            decoration: InputDecoration(
              hintText: 'Ex: Ohana Delivery',
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),

          const Text('URL', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _urlIntegracaoController,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: 'https://.../api/motoboy/nome',
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _salvandoIntegracao ? null : _salvarIntegracao,
              child: _salvandoIntegracao
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('CADASTRAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemIntegracao(Map<String, dynamic> integracao) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.sync_alt, color: Colors.purple, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(integracao['nome'] as String, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(_nomeDoMotoboy(integracao['motoboyUid'] as String),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text(integracao['url'] as String,
                  style: const TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => _removerIntegracao(integracao['id'] as int),
          child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
        ),
      ]),
    );
  }

  Widget _formularioNovo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vincular motoboy a um restaurante',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Merchant ID: copia da tela "Entregadores" > "Usar serviço de entrega" > Motoca Premium, na Saipos.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 16),

          const Text('Motoboy', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          SelecionarMotoboy(
            opcoes: _opcoesMotoboys,
            onSelecionado: (v) => setState(() => _motoboySelecionadoUid = v),
            onControllerReady: (c) => _motoboyFieldController = c,
          ),
          const SizedBox(height: 14),

          const Text('Conta de restaurante (opcional)', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0xFF1B2435), borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                dropdownColor: const Color(0xFF1B2435),
                value: _restauranteSelecionadoUid,
                hint: const Text('Nenhum', style: TextStyle(color: Colors.white38)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
                  ..._restaurantes.map((u) => DropdownMenuItem<String?>(
                        value: u['uid'] as String,
                        child: Text('${u['nome']} (${u['email']})', overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _restauranteSelecionadoUid = v),
              ),
            ),
          ),
          const SizedBox(height: 14),

          const Text('Nome do restaurante', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _nomeRestauranteController,
            decoration: InputDecoration(
              hintText: 'Ex: Treduarte Pizzaria',
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),

          const Text('Merchant ID (da Saipos)', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _merchantIdController,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ex: 38f48430-6e62-4273-8510-6ea638d8b524',
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _gerando ? null : _gerarCredenciais,
              child: _gerando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('GERAR CREDENCIAIS', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grupoRestaurante(MapEntry<String, List<Map<String, dynamic>>> grupo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.storefront, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(grupo.key, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 10),
            ...grupo.value.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white38, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_nomeDoMotoboy(r['motoboyUid'] as String),
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                      GestureDetector(
                        onTap: () => _remover(r),
                        child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
