// Fala com backend/src/routes/restauranteLojas.ts — geração self-service de
// Merchant ID/Client ID/Secret pra um motoboy, direto do painel do
// restaurante (mesma ideia de lib/pedidos/pedidos_api.dart, autenticado com
// o ID token do Firebase do próprio restaurante logado).
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../chat/chat_service.dart';

class RestauranteLojasApiException implements Exception {
  final String mensagem;
  RestauranteLojasApiException(this.mensagem);

  @override
  String toString() => mensagem;
}

class RestauranteLojasApi {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  static Future<Map<String, String>> _headers() async {
    final token = await ChatService.getIdToken();
    if (token == null) {
      throw RestauranteLojasApiException('Sessão expirada. Saia e entre de novo no app.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<http.Response> _tentar(Future<http.Response> Function() chamada) async {
    try {
      return await chamada().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw RestauranteLojasApiException('A conexão demorou demais. Tente de novo.');
    } on http.ClientException {
      throw RestauranteLojasApiException('Erro de conexão. Verifique sua internet.');
    }
  }

  /// Gera um Merchant/Client ID/Secret novo. Lança
  /// [RestauranteLojasApiException] com mensagem pronta se o Merchant ID já
  /// estiver cadastrado (409).
  static Future<Map<String, dynamic>> criar({
    required String merchantId,
    required String motoboyUid,
    required String nomeRestaurante,
  }) async {
    final headers = await _headers();
    final resp = await _tentar(() => http.post(
          Uri.parse('$_baseUrl/api/restaurante/lojas'),
          headers: headers,
          body: jsonEncode({'merchantId': merchantId, 'motoboyUid': motoboyUid, 'nomeRestaurante': nomeRestaurante}),
        ));

    if (resp.statusCode == 201) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    if (resp.statusCode == 409) {
      throw RestauranteLojasApiException('Esse Merchant ID já está cadastrado.');
    }
    if (resp.statusCode == 401) {
      throw RestauranteLojasApiException('Sessão expirada. Saia e entre de novo no app.');
    }
    throw RestauranteLojasApiException('Não consegui gerar as credenciais agora. Tente de novo.');
  }

  /// Lista as credenciais já geradas desse restaurante (sem o secret).
  static Future<List<Map<String, dynamic>>> listar() async {
    final headers = await _headers();
    final resp = await _tentar(() => http.get(Uri.parse('$_baseUrl/api/restaurante/lojas'), headers: headers));

    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['registros'] as List).cast<Map<String, dynamic>>();
  }

  /// Desativa uma credencial (não apaga de verdade — ver
  /// backend/src/routes/restauranteLojas.ts). Lança
  /// [RestauranteLojasApiException] com mensagem pronta se não achar o
  /// registro (404 — já foi desativado, ou não pertence a esse restaurante)
  /// ou qualquer outro erro.
  static Future<void> remover(int id) async {
    final headers = await _headers();
    final resp = await _tentar(() => http.delete(Uri.parse('$_baseUrl/api/restaurante/lojas/$id'), headers: headers));

    if (resp.statusCode == 200) return;
    if (resp.statusCode == 404) {
      throw RestauranteLojasApiException('Esse registro já não existe mais.');
    }
    if (resp.statusCode == 401) {
      throw RestauranteLojasApiException('Sessão expirada. Saia e entre de novo no app.');
    }
    throw RestauranteLojasApiException('Não consegui desativar agora. Tente de novo.');
  }

  /// Busca de novo o Client ID/Secret de uma credencial já existente (o
  /// secret só aparece uma vez ao gerar — isso permite ver de novo depois).
  static Future<Map<String, dynamic>> verCredenciais(int id) async {
    final headers = await _headers();
    final resp = await _tentar(() => http.get(Uri.parse('$_baseUrl/api/restaurante/lojas/$id/segredo'), headers: headers));

    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    if (resp.statusCode == 404) {
      throw RestauranteLojasApiException('Esse registro já não existe mais.');
    }
    if (resp.statusCode == 401) {
      throw RestauranteLojasApiException('Sessão expirada. Saia e entre de novo no app.');
    }
    throw RestauranteLojasApiException('Não consegui buscar as credenciais agora. Tente de novo.');
  }
}
