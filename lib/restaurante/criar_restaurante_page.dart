// Tela do painel Admin pra criar um login de restaurante novo — depois de
// criado, o restaurante entra com esse email/senha na tela normal de login
// do app e cai direto na tela dele (ver login_page.dart/app_shell.dart,
// que checam ChatService.buscarTipoUsuario).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../admin.dart';
import 'restaurante_service.dart';

class CriarRestaurantePage extends StatefulWidget {
  const CriarRestaurantePage({super.key});

  @override
  State<CriarRestaurantePage> createState() => _CriarRestaurantePageState();
}

class _CriarRestaurantePageState extends State<CriarRestaurantePage> {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  String _nome = '';
  bool _criando = false;
  List<String> _nomesSugeridos = [];
  TextEditingController? _nomeFieldController;

  @override
  void initState() {
    super.initState();
    _carregarSugestoes();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  /// Nomes de restaurante já cadastrados via loja Saipos (`nomeRestaurante`)
  /// que ainda não têm nenhum login de restaurante vinculado — pra sugerir
  /// aqui em vez do admin ter que digitar de novo (e arriscar um nome
  /// diferente do que já está integrado).
  Future<void> _carregarSugestoes() async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/admin/lojas'), headers: {'X-Admin-Key': kAdminApiKey})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final registros = (data['registros'] as List).cast<Map<String, dynamic>>();

      final semLogin = <String>{};
      final comLogin = <String>{};
      for (final r in registros) {
        final nome = r['nomeRestaurante'] as String;
        if (r['restauranteUid'] != null) {
          comLogin.add(nome);
        } else {
          semLogin.add(nome);
        }
      }
      semLogin.removeAll(comLogin);

      if (!mounted) return;
      setState(() {
        _nomesSugeridos = semLogin.toList()..sort();
      });
    } catch (_) {
      // Sem sugestões não impede o admin de digitar o nome na mão.
    }
  }

  Future<void> _criar() async {
    final nome = _nome.trim();
    final email = _emailController.text.trim();
    final senha = _senhaController.text.trim();

    if (nome.isEmpty || email.isEmpty || senha.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Preenche nome, email e uma senha com pelo menos 6 caracteres.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _criando = true);
    try {
      await RestauranteService.criarContaRestaurante(nome: nome, email: email, senha: senha);
      if (!mounted) return;
      await _mostrarCredenciaisGeradas(email: email, senha: senha);
      setState(() => _nome = '');
      _nomeFieldController?.clear();
      _emailController.clear();
      _senhaController.clear();
      await _carregarSugestoes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao criar: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _criando = false);
    }
  }

  Future<void> _mostrarCredenciaisGeradas({required String email, required String senha}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.storefront, color: Colors.green),
          SizedBox(width: 10),
          Text('Login criado!'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Passa esse email e senha pro restaurante — ele entra com isso na tela de login normal do app.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _campoCopiavel('Email', email),
            const SizedBox(height: 10),
            _campoCopiavel('Senha', senha),
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

  Widget _campoNomeRestaurante() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Autocomplete<String>(
          optionsBuilder: (TextEditingValue valor) {
            if (valor.text.isEmpty) return _nomesSugeridos;
            final busca = valor.text.toLowerCase();
            return _nomesSugeridos.where((n) => n.toLowerCase().contains(busca));
          },
          onSelected: (selecao) => setState(() => _nome = selecao),
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            _nomeFieldController = controller;
            return TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: (v) => _nome = v,
              decoration: InputDecoration(
                hintText: 'Ex: Treduarte Pizzaria',
                filled: true,
                fillColor: const Color(0xFF1B2435),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: const Color(0xFF1B2435),
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: 220),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final opcao = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.storefront, color: Colors.white38, size: 18),
                        title: Text(opcao, style: const TextStyle(fontSize: 14)),
                        onTap: () => onSelected(opcao),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
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
                child: Text(valor, style: const TextStyle(fontFamily: 'monospace', fontSize: 14), overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.copy, color: Colors.white38, size: 16),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        title: const Text('Criar restaurante'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Novo login de restaurante', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'Cria uma conta pra esse restaurante configurar as próprias taxas por bairro e vincular motoboys.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  const Text('Nome do restaurante', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text(
                    'Escolha um restaurante já cadastrado (loja Saipos) ou digite um nome novo.',
                    style: TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  _campoNomeRestaurante(),
                  const SizedBox(height: 14),

                  const Text('Email', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'contato@restaurante.com',
                      filled: true,
                      fillColor: const Color(0xFF1B2435),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text('Senha', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _senhaController,
                    decoration: InputDecoration(
                      hintText: 'Mínimo 6 caracteres',
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
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _criando ? null : _criar,
                      child: _criando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('CRIAR LOGIN', style: TextStyle(fontWeight: FontWeight.bold)),
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
}
