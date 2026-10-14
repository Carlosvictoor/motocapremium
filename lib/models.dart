// Os "moldes" de dados do app: uma saída (entrega), um dia de trabalho, um
// gasto e um mês já fechado. Nenhuma dessas classes fala com o banco de
// dados — elas só guardam os valores; quem lê/grava no banco é o DB
// (database_io.dart / database_stub.dart).
import 'package:flutter/material.dart';

/// Uma saída (entrega) registrada no dia: os valores que o motoboy recebeu
/// (Paga, Taxa, Gorjeta) e as comandas do pedido.
class Saida {
  final int? dbId;
  final DateTime hora;
  final String? paga;
  final String? taxa;
  final String? gorjeta;
  final String? comandas;

  Saida({
    this.dbId,
    required this.hora,
    this.paga,
    this.taxa,
    this.gorjeta,
    this.comandas,
  });

  /// Soma Paga + Taxa + Gorjeta dessa saída (o que ela rendeu no total).
  double get valorTotal {
    double t = 0;
    if (paga != null) t += double.tryParse(paga!.replaceAll(',', '.')) ?? 0;
    if (taxa != null) t += double.tryParse(taxa!.replaceAll(',', '.')) ?? 0;
    if (gorjeta != null) t += double.tryParse(gorjeta!.replaceAll(',', '.')) ?? 0;
    return t;
  }

  /// Hora da saída no formato "HH:mm".
  String get horaStr =>
      "${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}";

  /// Só conta como saída de verdade quando tem Taxa e/ou Comanda — registrar
  /// apenas Paga e/ou Gorjeta é considerado um valor avulso, não uma entrega.
  bool get contaComoSaida =>
      (taxa != null && taxa!.trim().isNotEmpty) ||
      (comandas != null && comandas!.trim().isNotEmpty);
}

/// Um dia de trabalho já fechado (depois de apertar "Zerar o dia"): guarda
/// todas as saídas daquele dia, mais o KM rodado e o tempo online.
class DiaRegistro {
  final int? dbId;
  final DateTime data;
  final List<Saida> saidas;
  final double kmRodado;
  final int tempoOnlineMin;

  DiaRegistro({
    this.dbId,
    required this.data,
    required this.saidas,
    this.kmRodado = 0,
    this.tempoOnlineMin = 0,
  });

  /// Soma o valor de todas as saídas do dia.
  double get total => saidas.fold(0.0, (s, r) => s + r.valorTotal);

  /// Quantas saídas do dia contam como entrega de verdade (ver
  /// [Saida.contaComoSaida]).
  int get totalSaidas => saidas.where((s) => s.contaComoSaida).length;
}

/// Um gasto lançado na aba Financeiro (combustível, alimentação,
/// manutenção ou outros).
class Gasto {
  final int? dbId;
  final String descricao;
  final double valor;
  final DateTime data;
  final Color cor;
  final IconData icone;
  final String categoria;

  Gasto({
    this.dbId,
    required this.descricao,
    required this.valor,
    required this.data,
    required this.cor,
    required this.icone,
    required this.categoria,
  });
}

/// Um mês já fechado (depois de apertar "Fechar Mês"): guarda todos os
/// dias e gastos daquele mês, pra aparecer no histórico de Meses Fechados.
class MesFechado {
  final int? dbId;
  final int mes;
  final int ano;
  final List<DiaRegistro> dias;
  final List<Gasto> gastos;

  MesFechado({
    this.dbId,
    required this.mes,
    required this.ano,
    required this.dias,
    required this.gastos,
  });

  /// Soma o ganho de todos os dias do mês.
  double get totalGanho => dias.fold(0, (s, d) => s + d.total);

  /// Soma todos os gastos do mês.
  double get totalGastos => gastos.fold(0, (s, g) => s + g.valor);

  /// Ganho do mês menos os gastos do mês.
  double get saldo => totalGanho - totalGastos;
}
