// Lista completa dos dias registrados (aberta a partir de "Ver todas as
// atividades" na aba Resumo, que só mostra os 3 mais recentes).
import 'package:flutter/material.dart';
import 'models.dart';
import 'utils.dart';

class AtividadesPage extends StatelessWidget {
  final List<DiaRegistro> dias;

  const AtividadesPage({super.key, required this.dias});

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        title: const Text('Todas as atividades'),
      ),
      body: SafeArea(
        child: dias.isEmpty
            ? const Center(
                child: Text('Nenhuma atividade registrada ainda.', style: TextStyle(color: Colors.white38)),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(18),
                itemCount: dias.length,
                itemBuilder: (context, i) => _diaRow(dias[i]),
              ),
      ),
    );
  }

  Widget _diaRow(DiaRegistro dia) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.blue, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatarData(dia.data), style: const TextStyle(fontSize: 15)),
                if (dia.kmRodado > 0 || dia.tempoOnlineMin > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '🛣️ ${dia.kmRodado.toStringAsFixed(1)} km  •  ⏱ ${formatarDuracaoMin(dia.tempoOnlineMin)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          Text('${dia.totalSaidas} saída${dia.totalSaidas != 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(width: 12),
          Text('R\$ ${dia.total.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
