// Card de um pedido: número, restaurante, endereço, valor, taxa, pagamento,
// status e observações — reaproveitado tanto na lista da aba Pedidos quanto
// no resultado do scan (pedidos_tab.dart).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pedidos_models.dart';

class PedidoCard extends StatelessWidget {
  final Pedido pedido;
  final bool aceitando;
  final bool finalizando;
  final VoidCallback? onAceitar;
  final VoidCallback? onFinalizar;

  const PedidoCard({
    super.key,
    required this.pedido,
    this.aceitando = false,
    this.finalizando = false,
    this.onAceitar,
    this.onFinalizar,
  });

  Future<void> _abrirMapa() async {
    final endereco = pedido.endereco;
    if (endereco == null || endereco.trim().isEmpty) return;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pedido #${pedido.orderDisplayId ?? pedido.orderId}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _statusChip(),
            ],
          ),
          if (pedido.restaurante != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.storefront, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pedido.restaurante!,
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ]),
          ],
          if (pedido.endereco != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pedido.endereco!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ]),
          ],
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.credit_card, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text(pedido.pagamentoLabel, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
          if (pedido.observacoes != null && pedido.observacoes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.notes, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pedido.observacoes!,
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Valor', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    Text('R\$ ${pedido.valorPedido.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Taxa', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    Text('R\$ ${pedido.taxaMotoboy.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ),
            ],
          ),
          if (pedido.disponivel) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: aceitando ? null : onAceitar,
                child: aceitando
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('ACEITAR ENTREGA',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
          ],
          if (pedido.aceito) ...[
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
                      onPressed: _abrirMapa,
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
                      onPressed: finalizando ? null : onFinalizar,
                      icon: finalizando
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('FINALIZAR',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip() {
    final Color cor = switch (pedido.status) {
      'DISPONIVEL' => Colors.blue,
      'ACEITA' || 'RETIRADA' || 'EM_ENTREGA' => Colors.orange,
      'ENTREGUE' => Colors.green,
      _ => Colors.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
      child: Text(pedido.statusLabel,
          style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
