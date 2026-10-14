// Fala com backend/src/routes/restauranteFinanceiro.ts — histórico dia a
// dia de vendas/crédito/débito/dinheiro/pix pra aba Financeiro (Fase 13).
// "Meses fechados" fecha sozinho todo início de mês (automático, sem
// precisar de botão) — congela um snapshot dos totais do mês anterior e
// reseta o período "atual" da tela, sem apagar nenhum dado bruto. Mesmo
// padrão de lib/restaurante/restaurante_relatorio_api.dart.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../chat/chat_service.dart';

class DiaFinanceiro {
  final DateTime data;
  final int saidas;
  final double totalTaxas;
  final double totalVendas;
  final double totalCredito;
  final double totalDebito;
  final double totalCartao;
  final double totalDinheiro;
  final double totalPix;
  final double totalOutros;

  DiaFinanceiro({
    required this.data,
    required this.saidas,
    required this.totalTaxas,
    required this.totalVendas,
    required this.totalCredito,
    required this.totalDebito,
    required this.totalCartao,
    required this.totalDinheiro,
    required this.totalPix,
    required this.totalOutros,
  });

  factory DiaFinanceiro.fromJson(Map<String, dynamic> json) => DiaFinanceiro(
    data: DateTime.tryParse(json['data'] as String? ?? '') ?? DateTime.now(),
    saidas: json['saidas'] as int? ?? 0,
    totalTaxas: ((json['totalTaxasCents'] as num?) ?? 0) / 100,
    totalVendas: ((json['totalVendasCents'] as num?) ?? 0) / 100,
    totalCredito: ((json['totalCreditoCents'] as num?) ?? 0) / 100,
    totalDebito: ((json['totalDebitoCents'] as num?) ?? 0) / 100,
    totalCartao: ((json['totalCartaoCents'] as num?) ?? 0) / 100,
    totalDinheiro: ((json['totalDinheiroCents'] as num?) ?? 0) / 100,
    totalPix: ((json['totalPixCents'] as num?) ?? 0) / 100,
    totalOutros: ((json['totalOutrosCents'] as num?) ?? 0) / 100,
  );
}

class MesFechado {
  final int id;
  final DateTime periodoInicio;
  final DateTime periodoFim;
  final int saidas;
  final double totalTaxas;
  final double totalVendas;
  final double totalCredito;
  final double totalDebito;
  final double totalCartao;
  final double totalDinheiro;
  final double totalPix;
  final double totalOutros;

  MesFechado({
    required this.id,
    required this.periodoInicio,
    required this.periodoFim,
    required this.saidas,
    required this.totalTaxas,
    required this.totalVendas,
    required this.totalCredito,
    required this.totalDebito,
    required this.totalCartao,
    required this.totalDinheiro,
    required this.totalPix,
    required this.totalOutros,
  });

  factory MesFechado.fromJson(Map<String, dynamic> json) => MesFechado(
    id: json['id'] as int? ?? 0,
    periodoInicio:
        DateTime.tryParse(json['periodoInicio'] as String? ?? '') ??
        DateTime.now(),
    periodoFim:
        DateTime.tryParse(json['periodoFim'] as String? ?? '') ??
        DateTime.now(),
    saidas: json['saidas'] as int? ?? 0,
    totalTaxas: ((json['totalTaxasCents'] as num?) ?? 0) / 100,
    totalVendas: ((json['totalVendasCents'] as num?) ?? 0) / 100,
    totalCredito: ((json['totalCreditoCents'] as num?) ?? 0) / 100,
    totalDebito: ((json['totalDebitoCents'] as num?) ?? 0) / 100,
    totalCartao: ((json['totalCartaoCents'] as num?) ?? 0) / 100,
    totalDinheiro: ((json['totalDinheiroCents'] as num?) ?? 0) / 100,
    totalPix: ((json['totalPixCents'] as num?) ?? 0) / 100,
    totalOutros: ((json['totalOutrosCents'] as num?) ?? 0) / 100,
  );
}

class RestauranteFinanceiroApi {
  static const _baseUrl =
      'https://motoca-premium-backend.motoca-premium.workers.dev';

  static Future<Map<String, String>> _headers() async {
    final token = await ChatService.getIdToken();
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Nunca lança exceção — se der erro de rede, devolve lista vazia (essa
  /// aba é secundária, não deve travar o painel do restaurante).
  static Future<List<DiaFinanceiro>> buscarHistorico({int dias = 30}) async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return [];
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/api/restaurante/financeiro?dias=$dias'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['historico'] as List<dynamic>? ?? [])
          .map((d) => DiaFinanceiro.fromJson(d as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<MesFechado>> listarFechados() async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return [];
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/api/restaurante/financeiro/fechados'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['fechados'] as List<dynamic>? ?? [])
          .map((d) => MesFechado.fromJson(d as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Reset rápido: ao contrário do fechamento automático de mês (ver
  /// backend/src/routes/restauranteFinanceiro.ts autoFecharSeVirouMes),
  /// NÃO guarda snapshot nenhum — apaga todo o histórico de "Meses
  /// fechados" e zera o período atual. Não apaga pedido/entrega nenhum,
  /// só o resumo.
  static Future<bool> zerarTudo() async {
    try {
      final headers = await _headers();
      if (headers.isEmpty) return false;
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/api/restaurante/financeiro/zerar-tudo'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
