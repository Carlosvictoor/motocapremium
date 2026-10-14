// Pedido vindo de uma integração externa de leitura (outro sistema de
// delivery, fora a Saipos — ver backend/src/routes/integracoesExternas.ts).
// Só visualização: não tem status de aceite/finalização por aqui.
class EntregaExterna {
  final String pedido;
  final String cliente;
  final String endereco;
  final String formaPagamento;
  final double valorCobrar;
  final double taxa;
  final String status;
  final String loja;
  final String localizador;
  final String dataHora;

  EntregaExterna({
    required this.pedido,
    required this.cliente,
    required this.endereco,
    required this.formaPagamento,
    required this.valorCobrar,
    required this.taxa,
    required this.status,
    required this.loja,
    required this.localizador,
    required this.dataHora,
  });

  /// Se o pedido já está pago — heurística baseada em texto, já que o
  /// sistema externo não manda um campo booleano dedicado pra isso (só o
  /// texto da forma de pagamento, tipo "ONLINE (PAGO)").
  bool get pago => formaPagamento.toLowerCase().contains('pago');

  /// Cópia com a taxa trocada — usado quando o restaurante tem a
  /// sobreposição por bairro ligada (ver taxa_override_service.dart).
  EntregaExterna copyWithTaxa(double novaTaxa) => EntregaExterna(
        pedido: pedido,
        cliente: cliente,
        endereco: endereco,
        formaPagamento: formaPagamento,
        valorCobrar: valorCobrar,
        taxa: novaTaxa,
        status: status,
        loja: loja,
        localizador: localizador,
        dataHora: dataHora,
      );

  factory EntregaExterna.fromJson(Map<String, dynamic> json) => EntregaExterna(
        pedido: json['pedido'] as String? ?? '',
        cliente: json['cliente'] as String? ?? '',
        endereco: json['endereco'] as String? ?? '',
        formaPagamento: json['formaPagamento'] as String? ?? '',
        valorCobrar: (json['valorCobrar'] as num?)?.toDouble() ?? 0,
        taxa: (json['taxa'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? '',
        loja: json['loja'] as String? ?? '',
        localizador: json['localizador'] as String? ?? '',
        dataHora: json['dataHora'] as String? ?? '',
      );
}

/// Um sistema externo cadastrado (ex.: "Ohana Delivery") com o status da
/// última busca e os pedidos que ele devolveu.
class IntegracaoExterna {
  final int id;
  final String nome;
  final String status; // ok | indisponivel | bloqueado
  final String? restauranteUid;
  final List<EntregaExterna> pedidos;

  IntegracaoExterna({required this.id, required this.nome, required this.status, this.restauranteUid, required this.pedidos});

  factory IntegracaoExterna.fromJson(Map<String, dynamic> json) => IntegracaoExterna(
        id: json['id'] as int? ?? 0,
        nome: json['nome'] as String? ?? '',
        status: json['status'] as String? ?? 'indisponivel',
        restauranteUid: json['restauranteUid'] as String?,
        pedidos: (json['pedidos'] as List<dynamic>? ?? [])
            .map((p) => EntregaExterna.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  /// Cópia com a lista de pedidos trocada — usado depois de aplicar a
  /// sobreposição de taxa por bairro em cada pedido.
  IntegracaoExterna copyWithPedidos(List<EntregaExterna> novosPedidos) => IntegracaoExterna(
        id: id,
        nome: nome,
        status: status,
        restauranteUid: restauranteUid,
        pedidos: novosPedidos,
      );
}
