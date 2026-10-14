// Fala com backend/src/routes/restauranteRelatorio.ts — relatório de
// saídas/comandas/total por motoboy desse restaurante (Fase 12). Mesmo
// padrão de lib/restaurante/restaurante_lojas_api.dart.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../chat/chat_service.dart';

class ComandaRelatorio {
  final String referencia;
  final double taxa;
  final String data;

  ComandaRelatorio({required this.referencia, required this.taxa, required this.data});

  factory ComandaRelatorio.fromJson(Map<String, dynamic> json) => ComandaRelatorio(
        referencia: json['referencia'] as String? ?? '',
        taxa: ((json['taxaCents'] as num?) ?? 0) / 100,
        data: json['data'] as String? ?? '',
      );
}

class MotoboyRelatorio {
  final String motoboyUid;
  final int saidasHoje;
  final double totalHoje;
  final List<ComandaRelatorio> comandas;
  final int saidasHistorico;
  final double totalHistorico;

  MotoboyRelatorio({
    required this.motoboyUid,
    required this.saidasHoje,
    required this.totalHoje,
    required this.comandas,
    required this.saidasHistorico,
    required this.totalHistorico,
  });

  factory MotoboyRelatorio.fromJson(Map<String, dynamic> json) {
    final hoje = json['hoje'] as Map<String, dynamic>? ?? {};
    return MotoboyRelatorio(
      motoboyUid: json['motoboyUid'] as String? ?? '',
      saidasHoje: hoje['saidas'] as int? ?? 0,
      totalHoje: ((hoje['totalCents'] as num?) ?? 0) / 100,
      comandas: (hoje['comandas'] as List<dynamic>? ?? [])
          .map((c) => ComandaRelatorio.fromJson(c as Map<String, dynamic>))
          .toList(),
      saidasHistorico: json['historicoSaidas'] as int? ?? 0,
      totalHistorico: ((json['historicoTotalCents'] as num?) ?? 0) / 100,
    );
  }
}

class RelatorioRestaurante {
  final List<MotoboyRelatorio> motoboys;
  final int totalHojeSaidas;
  final double totalHojeValor;
  final double totalVendas;
  final double totalCredito;
  final double totalDebito;
  final double totalCartao;
  final double totalDinheiro;
  final double totalPix;
  final double totalOutros;

  RelatorioRestaurante({
    required this.motoboys,
    required this.totalHojeSaidas,
    required this.totalHojeValor,
    this.totalVendas = 0,
    this.totalCredito = 0,
    this.totalDebito = 0,
    this.totalCartao = 0,
    this.totalDinheiro = 0,
    this.totalPix = 0,
    this.totalOutros = 0,
  });

  factory RelatorioRestaurante.fromJson(Map<String, dynamic> json) => RelatorioRestaurante(
        motoboys: (json['motoboys'] as List<dynamic>? ?? [])
            .map((m) => MotoboyRelatorio.fromJson(m as Map<String, dynamic>))
            .toList(),
        totalHojeSaidas: json['totalHojeSaidas'] as int? ?? 0,
        totalHojeValor: ((json['totalHojeCents'] as num?) ?? 0) / 100,
        totalVendas: ((json['totalVendasCents'] as num?) ?? 0) / 100,
        totalCredito: ((json['totalCreditoCents'] as num?) ?? 0) / 100,
        totalDebito: ((json['totalDebitoCents'] as num?) ?? 0) / 100,
        totalCartao: ((json['totalCartaoCents'] as num?) ?? 0) / 100,
        totalDinheiro: ((json['totalDinheiroCents'] as num?) ?? 0) / 100,
        totalPix: ((json['totalPixCents'] as num?) ?? 0) / 100,
        totalOutros: ((json['totalOutrosCents'] as num?) ?? 0) / 100,
      );

  static RelatorioRestaurante vazio() => RelatorioRestaurante(motoboys: [], totalHojeSaidas: 0, totalHojeValor: 0);
}

class RestauranteRelatorioApi {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  /// Nunca lança exceção — se der erro de rede, devolve relatório vazio
  /// (essa aba é secundária, não deve travar o painel do restaurante).
  static Future<RelatorioRestaurante> buscar() async {
    try {
      final token = await ChatService.getIdToken();
      if (token == null) return RelatorioRestaurante.vazio();
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/restaurante/relatorio'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return RelatorioRestaurante.vazio();
      return RelatorioRestaurante.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return RelatorioRestaurante.vazio();
    }
  }

  /// Zera manualmente o período "hoje" desse motoboy no relatório (Fase
  /// 12.1) — não mexe no Financeiro pessoal dele nem no relatório dele em
  /// outro restaurante, só nesse. Devolve `true` se conseguiu.
  static Future<bool> zerarDia(String motoboyUid) async {
    try {
      final token = await ChatService.getIdToken();
      if (token == null) return false;
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/api/restaurante/relatorio/zerar/$motoboyUid'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
