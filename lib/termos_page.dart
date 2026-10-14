// Termos de uso e política de privacidade. TEXTO PLACEHOLDER — ainda não é
// um termo jurídico revisado; antes de divulgar o app pra mais gente
// (principalmente agora que ele pede CPF e processa pagamento via Pix),
// vale trocar esse texto por um termo de verdade.
import 'package:flutter/material.dart';

class TermosPage extends StatelessWidget {
  const TermosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        title: const Text('Termos e privacidade'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secao(
                'Sobre o Motoca Premium',
                'O Motoca Premium é um app de apoio financeiro pra motoboys, '
                    'usado pra registrar entregas, ganhos e gastos do dia a dia, '
                    'além de integrar com parceiros de logística.',
              ),
              _secao(
                'Dados que coletamos',
                'Guardamos as informações que você preenche no app (nome, email, '
                    'telefone, CPF, dados do veículo) e os registros de entregas, '
                    'ganhos e gastos que você lança. Esses dados ficam vinculados '
                    'à sua conta e não são compartilhados com terceiros fora do '
                    'necessário pra operação do app (ex.: processar um pagamento).',
              ),
              _secao(
                'Pagamentos',
                'Cobranças via Pix são processadas pela Mercado Pago. O Motoca '
                    'Premium não armazena dados de cartão nem senha bancária.',
              ),
              _secao(
                'Exclusão de dados',
                'Você pode pedir a exclusão da sua conta e dos seus dados a '
                    'qualquer momento pela Central de Ajuda.',
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Este texto é um modelo simples e ainda não foi revisado '
                  'juridicamente.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secao(String titulo, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(texto, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }
}
