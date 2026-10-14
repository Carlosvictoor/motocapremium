// Dialog que pede o código de 4 dígitos que o cliente passa pro motoboy,
// pra pedidos que a Saipos marcou como confirmationCodeRequired. Confirma
// com o backend (que confirma com a Saipos) antes de finalizar a entrega.
import 'package:flutter/material.dart';
import 'pedidos_api.dart';

/// Mostra o dialog de código; devolve true se a entrega foi confirmada E
/// finalizada com sucesso, false/null caso contrário (usuário cancelou ou
/// deu erro — a mensagem de erro já é mostrada dentro do próprio dialog).
Future<bool?> mostrarDialogCodigoConfirmacao(BuildContext context, int pedidoId, double taxaEfetiva) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _CodigoConfirmacaoDialog(pedidoId: pedidoId, taxaEfetiva: taxaEfetiva),
  );
}

class _CodigoConfirmacaoDialog extends StatefulWidget {
  final int pedidoId;
  final double taxaEfetiva;
  const _CodigoConfirmacaoDialog({required this.pedidoId, required this.taxaEfetiva});

  @override
  State<_CodigoConfirmacaoDialog> createState() => _CodigoConfirmacaoDialogState();
}

class _CodigoConfirmacaoDialogState extends State<_CodigoConfirmacaoDialog> {
  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focos = List.generate(4, (_) => FocusNode());
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focos) {
      f.dispose();
    }
    super.dispose();
  }

  String get _codigo => _controllers.map((c) => c.text).join();

  Future<void> _confirmar() async {
    final codigo = _codigo;
    if (codigo.length != 4) {
      setState(() => _erro = 'Digite os 4 dígitos.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await PedidosApi.confirmarCodigo(widget.pedidoId, codigo);
      await PedidosApi.finalizar(widget.pedidoId, taxaEfetiva: widget.taxaEfetiva);
      if (mounted) Navigator.pop(context, true);
    } on PedidosApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D1117),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Código de entrega', style: TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Peça o código de 4 dígitos pro cliente e digite abaixo pra confirmar a entrega.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 50,
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focos[i],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF1B2435),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) {
                      if (v.isNotEmpty && i < 3) {
                        FocusScope.of(context).requestFocus(_focos[i + 1]);
                      }
                      if (v.isEmpty && i > 0) {
                        FocusScope.of(context).requestFocus(_focos[i - 1]);
                      }
                    },
                  ),
                ),
              );
            }),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _enviando ? null : _confirmar,
          child: _enviando
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Confirmar entrega', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
