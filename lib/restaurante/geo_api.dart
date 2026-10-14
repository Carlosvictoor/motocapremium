// Fala com backend/src/routes/geo.ts — estados/cidades (IBGE) e bairros
// de uma cidade (OpenStreetMap) pra ajudar o restaurante a cadastrar
// bairros em lote (Fase 13.2). Mesmo padrão de outros *_api.dart do
// painel do restaurante.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../chat/chat_service.dart';

class Estado {
  final String sigla;
  final String nome;
  const Estado({required this.sigla, required this.nome});
}

class GeoApi {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  static Future<Map<String, String>> _headers() async {
    final token = await ChatService.getIdToken();
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Nunca lança exceção — devolve lista vazia em caso de erro.
  static Future<List<Estado>> listarEstados() async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return [];
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/geo/estados'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['estados'] as List<dynamic>? ?? [])
          .map((e) => Estado(sigla: e['sigla'] as String, nome: e['nome'] as String))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> listarMunicipios(String uf) async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return [];
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/geo/municipios?uf=$uf'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['municipios'] as List<dynamic>? ?? []).cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// Busca os bairros conhecidos dessa cidade no OpenStreetMap — pode vir
  /// vazio pra cidades pequenas/pouco mapeadas (não é garantido completo),
  /// ou por erro temporário do servidor deles (fica em cache no backend
  /// depois da primeira vez, mas a primeira busca de uma cidade depende
  /// dele estar de pé). [erro] distingue os dois casos: `true` quando foi
  /// falha de verdade (vale tentar de novo), `false` quando é só uma
  /// cidade sem bairro conhecido mesmo.
  static Future<({List<String> bairros, bool erro})> buscarBairros(String cidade) async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return (bairros: <String>[], erro: true);
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/geo/bairros?cidade=${Uri.encodeQueryComponent(cidade)}'), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return (bairros: <String>[], erro: true);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final bairros = (data['bairros'] as List<dynamic>? ?? []).cast<String>();
      final erro = data['erro'] as bool? ?? false;
      return (bairros: bairros, erro: erro);
    } catch (_) {
      return (bairros: <String>[], erro: true);
    }
  }
}
