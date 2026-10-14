// Dialog que pede o código de confirmação (localizador) de uma entrega de
// integração externa — comum em pedidos vindos de agregadores tipo
// iFood/99, que dão um código curto pro cliente confirmar a entrega. A
// checagem é local (compara com o campo `localizador` que já veio na
// resposta da integração, sem chamar nenhum backend) porque o sistema
// externo é só leitura. Tem opção de pular e finalizar sem código.
import 'package:flutter/material.dart';

/// Mostra o dialog; devolve `true` se deve finalizar a entrega (código
/// confirmado OU o motoboy escolheu pular), `false`/`null` se cancelou.
Future<bool?> mostrarDialogCodigoExterno(BuildContext context, String localizadorEsperado) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _CodigoExternoDialog(localizadorEsperado: localizadorEsperado),
  );
}

class _CodigoExternoDialog extends StatefulWidget {
  final String localizadorEsperado;
  const _CodigoExternoDialog({required this.localizadorEsperado});

  @override
  State<_CodigoExternoDialog> createState() => _CodigoExternoDialogState();
}

class _CodigoExternoDialogState extends State<_CodigoExternoDialog> {
  final _controller = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final digitado = _controller.text.trim();
    if (digitado.isEmpty) {
      setState(() => _erro = 'Digite o código, ou toque em "Finalizar sem código".');
      return;
    }
    if (digitado.toUpperCase() != widget.localizadorEsperado.trim().toUpperCase()) {
      setState(() => _erro = 'Código incorreto.');
      return;
    }
    Navigator.pop(context, true);
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
            'Peça o código de confirmação pro cliente e digite abaixo, ou finalize sem código se não tiver.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
            decoration: InputDecoration(
              hintText: 'Ex: AB12CD',
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Finalizar sem código', style: TextStyle(color: Colors.orange)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _confirmar,
          child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
