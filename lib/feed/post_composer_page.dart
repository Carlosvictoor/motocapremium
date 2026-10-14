// Tela de "novo post": texto + as três estatísticas do dia (faturamento,
// entregas, km), pré-preenchidas com os dados reais de hoje mas editáveis
// antes de publicar.
import 'package:flutter/material.dart';
import 'feed_service.dart';

class PostComposerPage extends StatefulWidget {
  final String meuNome;
  final double faturamentoHoje;
  final int entregasHoje;
  final double kmHoje;

  const PostComposerPage({
    super.key,
    required this.meuNome,
    required this.faturamentoHoje,
    required this.entregasHoje,
    required this.kmHoje,
  });

  @override
  State<PostComposerPage> createState() => _PostComposerPageState();
}

class _PostComposerPageState extends State<PostComposerPage> {
  late final _textoController = TextEditingController();
  late final _faturamentoController =
      TextEditingController(text: widget.faturamentoHoje.toStringAsFixed(2));
  late final _entregasController = TextEditingController(text: widget.entregasHoje.toString());
  late final _kmController = TextEditingController(text: widget.kmHoje.toStringAsFixed(1));

  bool _publicando = false;
  String? _erro;

  @override
  void dispose() {
    _textoController.dispose();
    _faturamentoController.dispose();
    _entregasController.dispose();
    _kmController.dispose();
    super.dispose();
  }

  Future<void> _publicar() async {
    final texto = _textoController.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Escreva algo antes de publicar.');
      return;
    }
    setState(() {
      _publicando = true;
      _erro = null;
    });
    try {
      await FeedService.criarPost(
        texto: texto,
        autorNome: widget.meuNome,
        faturamento: double.tryParse(_faturamentoController.text.replaceAll(',', '.')) ?? 0,
        entregas: int.tryParse(_entregasController.text) ?? 0,
        km: double.tryParse(_kmController.text.replaceAll(',', '.')) ?? 0,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _publicando = false;
        _erro = 'Não deu pra publicar agora. Tente novamente.';
      });
    }
  }

  InputDecoration _campo(String rotulo, {String? prefixo}) {
    return InputDecoration(
      labelText: rotulo,
      labelStyle: const TextStyle(color: Colors.white54),
      prefixText: prefixo,
      prefixStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF0D1117),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.blue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        title: const Text('Publicar'),
        actions: [
          TextButton(
            onPressed: _publicando ? null : _publicar,
            child: _publicando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2),
                  )
                : const Text('Publicar', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _textoController,
                autofocus: true,
                maxLines: 5,
                maxLength: 2000,
                style: const TextStyle(fontSize: 16),
                decoration: _campo('O que rolou no seu dia?'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 4),
                Text(_erro!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Estatísticas de hoje',
                        style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _faturamentoController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _campo('Faturamento', prefixo: 'R\$ '),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _entregasController,
                      keyboardType: TextInputType.number,
                      decoration: _campo('Entregas'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _kmController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _campo('Km rodados'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
