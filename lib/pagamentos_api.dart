// Fala com o backend do Motoca Premium pra gerar e checar pagamentos Pix da
// assinatura mensal (só usado na Web, onde não existe Play Store — ver
// AssinaturaService). Mesmo padrão de lib/pedidos/pedidos_api.dart: manda o
// ID token do Firebase, trata erro de rede com mensagem pronta.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'chat/chat_service.dart';

class PagamentosApiException implements Exception {
  final String mensagem;
  PagamentosApiException(this.mensagem);

  @override
  String toString() => mensagem;
}

class PixGerado {
  final String qrCodeBase64;
  final String copiaCola;
  final DateTime expiraEm;

  PixGerado({required this.qrCodeBase64, required this.copiaCola, required this.expiraEm});

  factory PixGerado.fromJson(Map<String, dynamic> json) => PixGerado(
        qrCodeBase64: json['qrCodeBase64'] as String,
        copiaCola: json['copiaCola'] as String,
        expiraEm: DateTime.parse(json['expiraEm'] as String),
      );
}

class PagamentosApi {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  static Future<Map<String, String>> _headers() async {
    final token = await ChatService.getIdToken();
    if (token == null) {
      throw PagamentosApiException('Sessão expirada. Saia e entre de novo no app.');
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
      throw PagamentosApiException('A conexão demorou demais. Tente de novo.');
    } on http.ClientException {
      throw PagamentosApiException('Erro de conexão. Verifique sua internet.');
    }
  }

  /// Gera uma cobrança Pix nova de R$ 2,00 pra estender a assinatura em 30
  /// dias assim que for paga.
  static Future<PixGerado> criarPix() async {
    final headers = await _headers();
    final resp = await _tentar(() => http.post(Uri.parse('$_baseUrl/api/pagamentos'), headers: headers));

    if (resp.statusCode == 200) {
      return PixGerado.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    if (resp.statusCode == 401) {
      throw PagamentosApiException('Sessão expirada. Saia e entre de novo no app.');
    }
    throw PagamentosApiException('Não foi possível gerar o Pix agora. Tente de novo.');
  }

  /// Se a assinatura está ativa agora (por Pix) e até quando.
  static Future<({bool ativo, DateTime? expiraEm})> status() async {
    final headers = await _headers();
    final resp = await _tentar(() => http.get(Uri.parse('$_baseUrl/api/pagamentos/status'), headers: headers));

    if (resp.statusCode != 200) return (ativo: false, expiraEm: null);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final expiraStr = data['expiraEm'] as String?;
    return (ativo: data['ativo'] == true, expiraEm: expiraStr != null ? DateTime.parse(expiraStr) : null);
  }
}
