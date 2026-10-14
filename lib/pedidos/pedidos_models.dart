// Molde de um pedido/entrega vindo do backend do Motoca Premium (ver
// backend/src/lib/pedidoView.ts, que é quem monta esse JSON do lado do
// servidor). Espelha exatamente os campos de lá.

class Pedido {
  final int id;
  final String orderId;
  final String? orderDisplayId;
  final String deliveryId;
  final String status; // DISPONIVEL | ACEITA | RETIRADA | EM_ENTREGA | ENTREGUE | REJEITADA | CANCELADA
  final String? restaurante;
  final String? restauranteUid;
  final String? cliente;
  final String? endereco;
  final String? formaPagamento; // OFFLINE | ONLINE
  final String? tipoPagamento; // CREDIT | DEBIT | PIX | CASH | ...
  final double valorPedido;
  final double taxaMotoboy;
  final String? observacoes;
  final String? motoboyUid;
  final bool confirmationCodeRequired;

  Pedido({
    required this.id,
    required this.orderId,
    required this.orderDisplayId,
    required this.deliveryId,
    required this.status,
    required this.restaurante,
    this.restauranteUid,
    required this.cliente,
    required this.endereco,
    required this.formaPagamento,
    required this.tipoPagamento,
    required this.valorPedido,
    required this.taxaMotoboy,
    required this.observacoes,
    required this.motoboyUid,
    this.confirmationCodeRequired = false,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) {
    return Pedido(
      id: json['id'] as int,
      orderId: json['orderId'] as String,
      orderDisplayId: json['orderDisplayId'] as String?,
      deliveryId: json['deliveryId'] as String,
      status: json['status'] as String,
      restaurante: json['restaurante'] as String?,
      restauranteUid: json['restauranteUid'] as String?,
      cliente: json['cliente'] as String?,
      endereco: json['endereco'] as String?,
      formaPagamento: json['formaPagamento'] as String?,
      tipoPagamento: json['tipoPagamento'] as String?,
      valorPedido: (json['valorPedido'] as num?)?.toDouble() ?? 0,
      taxaMotoboy: (json['taxaMotoboy'] as num?)?.toDouble() ?? 0,
      observacoes: json['observacoes'] as String?,
      motoboyUid: json['motoboyUid'] as String?,
      confirmationCodeRequired: json['confirmationCodeRequired'] as bool? ?? false,
    );
  }

  /// Cópia do pedido com a taxa trocada — usado quando o restaurante tem a
  /// sobreposição por bairro ligada (ver lib/restaurante/taxa_override_service.dart)
  /// e a taxa mostrada/registrada precisa ser a do bairro, não a que veio
  /// no pedido.
  Pedido copyWithTaxa(double novaTaxa) => Pedido(
        id: id,
        orderId: orderId,
        orderDisplayId: orderDisplayId,
        deliveryId: deliveryId,
        status: status,
        restaurante: restaurante,
        restauranteUid: restauranteUid,
        cliente: cliente,
        endereco: endereco,
        formaPagamento: formaPagamento,
        tipoPagamento: tipoPagamento,
        valorPedido: valorPedido,
        taxaMotoboy: novaTaxa,
        observacoes: observacoes,
        motoboyUid: motoboyUid,
        confirmationCodeRequired: confirmationCodeRequired,
      );

  bool get disponivel => status == 'DISPONIVEL';
  bool get aceito => status == 'ACEITA';

  /// Texto amigável do status, pra mostrar no card.
  String get statusLabel {
    switch (status) {
      case 'DISPONIVEL': return 'Disponível';
      case 'ACEITA': return 'Aceito';
      case 'RETIRADA': return 'Retirado';
      case 'EM_ENTREGA': return 'Em entrega';
      case 'ENTREGUE': return 'Entregue';
      case 'REJEITADA': return 'Rejeitado';
      case 'CANCELADA': return 'Cancelado';
      default: return status;
    }
  }

  /// Texto amigável da forma/tipo de pagamento, pra mostrar no card.
  String get pagamentoLabel {
    if (formaPagamento == 'ONLINE') return 'Pago no app';
    switch (tipoPagamento) {
      case 'CREDIT': return 'Crédito';
      case 'DEBIT': return 'Débito';
      case 'PIX': return 'Pix';
      case 'CASH': return 'Dinheiro';
      case 'MEAL_VOUCHER': return 'Vale-refeição';
      case 'FOOD_VOUCHER': return 'Vale-alimentação';
      case 'CREDIT_DEBIT': return 'Crédito/Débito';
      default: return tipoPagamento ?? '—';
    }
  }
}
