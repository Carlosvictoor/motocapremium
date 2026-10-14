// Fala com o backend do Motoca Premium pra listar os pedidos de
// integrações externas de leitura (outros sistemas de delivery além da
// Saipos — ver backend/src/routes/integracoesExternas.ts). Mesmo padrão de
// lib/pedidos/pedidos_api.dart.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'chat/chat_service.dart';
import 'pedidos/entrega_externa_model.dart';

class IntegracoesApi {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  static Future<Map<String, String>> _headers() async {
    final token = await ChatService.getIdToken();
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Lista os pedidos de todas as integrações externas ativas desse
  /// motoboy. Nunca lança exceção pro chamador — se der erro de rede, só
  /// devolve lista vazia (essa seção é secundária, não deve travar a aba
  /// Pedidos).
  static Future<List<IntegracaoExterna>> listar() async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return [];
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/integracoes/pedidos'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['integracoes'] as List<dynamic>? ?? [])
          .map((i) => IntegracaoExterna.fromJson(i as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Marca um pedido de uma integração externa como finalizado — o sistema
  /// externo é só leitura, então isso só faz o pedido parar de aparecer na
  /// nossa lista (ver backend/src/routes/integracoesExternas.ts). [taxa] é
  /// a taxa efetiva (pode já vir sobreposta por bairro), [valorTotal] e
  /// [formaPagamento] alimentam o total de vendas/cartão/dinheiro/pix do
  /// relatório do restaurante (Fase 12.2). Devolve `true` se conseguiu.
  static Future<bool> finalizar(
    int integracaoId,
    String pedido, {
    required double taxa,
    required double valorTotal,
    required String formaPagamento,
  }) async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return false;
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/api/integracoes/$integracaoId/finalizar'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'pedido': pedido,
              'taxaCents': (taxa * 100).round(),
              'valorTotalCents': (valorTotal * 100).round(),
              'formaPagamento': formaPagamento,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
