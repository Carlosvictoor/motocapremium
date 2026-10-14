// Fala só com o backend do Motoca Premium (nunca direto com a Saipos — ver
// arquitetura no plano da Fase 1/3). Toda chamada manda o ID token do
// Firebase de quem está logado; o backend valida esse token (ver
// backend/src/lib/firebaseAuth.ts) e usa o uid pra saber quais lojas esse
// motoboy pode ver.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../chat/chat_service.dart';
import 'pedidos_models.dart';

/// Erro conhecido/tratável de uma chamada à API de pedidos, com mensagem já
/// pronta pra mostrar na tela.
class PedidosApiException implements Exception {
  final String mensagem;
  final int? statusCode;
  PedidosApiException(this.mensagem, [this.statusCode]);

  @override
  String toString() => mensagem;
}

class PedidosApi {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  static Future<Map<String, String>> _headers() async {
    final token = await ChatService.getIdToken();
    if (token == null) {
      throw PedidosApiException('Sessão expirada. Saia e entre de novo no app.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Envolve a chamada HTTP tratando erro de rede/timeout com uma mensagem
  /// amigável, igual pedido pelo usuário ("erro de conexão").
  static Future<http.Response> _tentar(Future<http.Response> Function() chamada) async {
    try {
      return await chamada().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw PedidosApiException('A conexão demorou demais. Tente de novo.');
    } on SocketException {
      throw PedidosApiException('Sem conexão com a internet.');
    } on http.ClientException {
      throw PedidosApiException('Erro de conexão. Verifique sua internet.');
    }
  }

  /// Escaneou um código de barras — o backend já acha o pedido E aceita a
  /// entrega na hora (não tem lista de "disponíveis" pra escolher: quem
  /// escaneia primeiro fica com a entrega). Lança PedidosApiException com
  /// mensagem pronta em caso de código não encontrado (404), pedido já
  /// aceito por outro motoboy (409) ou qualquer outro erro.
  static Future<Pedido> escanear(String barcode) async {
    final headers = await _headers();
    final resp = await _tentar(() => http.post(
          Uri.parse('$_baseUrl/api/deliveries/scan'),
          headers: headers,
          body: jsonEncode({'barcode': barcode, 'nome': AuthService.nomeLogado}),
        ));

    if (resp.statusCode == 200) {
      return Pedido.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    if (resp.statusCode == 404) {
      throw PedidosApiException('Pedido não encontrado pra esse código.', 404);
    }
    if (resp.statusCode == 409) {
      throw PedidosApiException('Esse pedido já foi aceito por outro motoboy.', 409);
    }
    if (resp.statusCode == 401) {
      throw PedidosApiException('Sessão expirada. Saia e entre de novo no app.', 401);
    }
    throw PedidosApiException('Não consegui procurar o pedido agora. Tente de novo.', resp.statusCode);
  }

  /// Aceita a entrega. Lança PedidosApiException com mensagem pronta se já
  /// tiver sido aceita por outro motoboy (409) ou não existir mais (404).
  /// Manda o nome de quem está logado — a Saipos exige o nome do entregador
  /// no evento de status (campo deliveryPerson), pra mostrar pro restaurante.
  static Future<Pedido> aceitar(int id) async {
    final headers = await _headers();
    final resp = await _tentar(() => http.post(
          Uri.parse('$_baseUrl/api/deliveries/$id/accept'),
          headers: headers,
          body: jsonEncode({'nome': AuthService.nomeLogado}),
        ));

    if (resp.statusCode == 200) {
      return Pedido.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    if (resp.statusCode == 409) {
      throw PedidosApiException('Esse pedido já foi aceito por outro motoboy.', 409);
    }
    if (resp.statusCode == 404) {
      throw PedidosApiException('Pedido não encontrado.', 404);
    }
    if (resp.statusCode == 401) {
      throw PedidosApiException('Sessão expirada. Saia e entre de novo no app.', 401);
    }
    throw PedidosApiException('Não consegui aceitar o pedido agora. Tente de novo.', resp.statusCode);
  }

  /// Confirma o código de 4 dígitos que o cliente passou pro motoboy.
  /// Precisa ter sucesso ANTES de chamar [finalizar] quando
  /// `confirmationCodeRequired` for true. Lança PedidosApiException com
  /// mensagem pronta se o código estiver errado (400) ou se essa validação
  /// ainda não estiver configurada do lado do backend (501).
  static Future<void> confirmarCodigo(int id, String codigo) async {
    final headers = await _headers();
    final resp = await _tentar(() => http.post(
          Uri.parse('$_baseUrl/api/deliveries/$id/confirmar-codigo'),
          headers: headers,
          body: jsonEncode({'codigo': codigo}),
        ));

    if (resp.statusCode == 200) return;
    if (resp.statusCode == 400) {
      throw PedidosApiException('Código incorreto.', 400);
    }
    if (resp.statusCode == 501) {
      throw PedidosApiException('Confirmação de código ainda não configurada. Fala com o suporte.', 501);
    }
    if (resp.statusCode == 401) {
      throw PedidosApiException('Sessão expirada. Saia e entre de novo no app.', 401);
    }
    throw PedidosApiException('Não consegui confirmar o código agora. Tente de novo.', resp.statusCode);
  }

  /// Finaliza a entrega. Se o pedido exigir código, [confirmarCodigo]
  /// precisa ter sido chamado com sucesso antes (o backend confere, não
  /// confia só no app). [taxaEfetiva] é a taxa que o motoboy realmente vai
  /// receber (pode já vir sobreposta por bairro, ver
  /// lib/restaurante/taxa_override_service.dart) — o backend só grava isso
  /// pro relatório interno do restaurante, não muda o que é mandado pra
  /// Saipos.
  static Future<Pedido> finalizar(int id, {required double taxaEfetiva}) async {
    final headers = await _headers();
    final resp = await _tentar(() => http.post(
          Uri.parse('$_baseUrl/api/deliveries/$id/finalizar'),
          headers: headers,
          body: jsonEncode({'taxaEfetivaCents': (taxaEfetiva * 100).round()}),
        ));

    if (resp.statusCode == 200) {
      return Pedido.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    if (resp.statusCode == 400) {
      throw PedidosApiException('Confirme o código de entrega antes de finalizar.', 400);
    }
    if (resp.statusCode == 404) {
      throw PedidosApiException('Pedido não encontrado.', 404);
    }
    if (resp.statusCode == 401) {
      throw PedidosApiException('Sessão expirada. Saia e entre de novo no app.', 401);
    }
    throw PedidosApiException('Não consegui finalizar a entrega agora. Tente de novo.', resp.statusCode);
  }

  /// Lista os pedidos disponíveis + os que esse motoboy já aceitou, e o
  /// total de taxas (somado no backend).
  static Future<({List<Pedido> pedidos, double totalTaxas})> listar() async {
    final headers = await _headers();
    final resp = await _tentar(() => http.get(
          Uri.parse('$_baseUrl/api/deliveries'),
          headers: headers,
        ));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final pedidos = (data['pedidos'] as List)
          .map((p) => Pedido.fromJson(p as Map<String, dynamic>))
          .toList();
      final totalTaxas = (data['totalTaxas'] as num?)?.toDouble() ?? 0;
      return (pedidos: pedidos, totalTaxas: totalTaxas);
    }
    if (resp.statusCode == 401) {
      throw PedidosApiException('Sessão expirada. Saia e entre de novo no app.', 401);
    }
    throw PedidosApiException('Não consegui carregar os pedidos agora.', resp.statusCode);
  }
}
