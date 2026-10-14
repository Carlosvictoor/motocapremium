// Campo de busca reutilizável pra escolher um motoboy — troca o dropdown
// simples (ruim de usar com uma lista grande) por um campo que filtra por
// nome ou email enquanto digita. Usado em admin_motoboys_page.dart e
// restaurante_dashboard.dart, todo lugar que hoje tem "Selecione um motoboy".
import 'package:flutter/material.dart';

class OpcaoMotoboy {
  final String uid;
  final String nome;
  final String email;
  const OpcaoMotoboy({required this.uid, required this.nome, required this.email});
}

class SelecionarMotoboy extends StatelessWidget {
  final List<OpcaoMotoboy> opcoes;
  final ValueChanged<String?> onSelecionado;
  final String hint;

  /// Chamado com o TextEditingController interno assim que ele é criado,
  /// pra quem estiver usando poder limpar o campo de fora (ex.: depois de
  /// vincular/gerar credenciais com sucesso) — mesmo truque já usado em
  /// lib/restaurante/criar_restaurante_page.dart.
  final void Function(TextEditingController)? onControllerReady;

  const SelecionarMotoboy({
    super.key,
    required this.opcoes,
    required this.onSelecionado,
    this.hint = 'Buscar motoboy por nome ou email',
    this.onControllerReady,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Autocomplete<OpcaoMotoboy>(
          displayStringForOption: (o) => '${o.nome} (${o.email})',
          optionsBuilder: (valor) {
            if (valor.text.isEmpty) return opcoes;
            final busca = valor.text.toLowerCase();
            return opcoes.where((o) => o.nome.toLowerCase().contains(busca) || o.email.toLowerCase().contains(busca));
          },
          onSelected: (o) => onSelecionado(o.uid),
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            onControllerReady?.call(controller);
            return TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: (texto) {
                if (texto.isEmpty) onSelecionado(null);
              },
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
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
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: 260),
                  child: options.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nenhum motoboy encontrado.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final o = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.two_wheeler, color: Colors.white38, size: 18),
                              title: Text(o.nome, style: const TextStyle(fontSize: 14)),
                              subtitle: Text(o.email, style: const TextStyle(color: Colors.white38, fontSize: 12), overflow: TextOverflow.ellipsis),
                              onTap: () => onSelected(o),
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
}
