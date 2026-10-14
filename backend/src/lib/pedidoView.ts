// Formata uma linha da tabela `pedidos` (join com `lojas` pro nome do
// restaurante) no JSON que o Flutter consome nas telas de Pedidos/scan.

export interface PedidoRow {
  id: number;
  order_id: string;
  order_display_id: string | null;
  delivery_id: string;
  status: string;
  restaurante_nome?: string;
  restaurante_uid?: string | null;
  customer_name: string | null;
  delivery_address: string | null;
  payment_method: string | null;
  payment_type: string | null;
  order_total_cents: number | null;
  delivery_fee_cents: number | null;
  observacoes: string | null;
  motoboy_uid: string | null;
  confirmation_code_required: number;
  codigo_confirmado: number;
  criado_em: string;
  atualizado_em: string;
}

export function pedidoParaJson(p: PedidoRow) {
  return {
    id: p.id,
    orderId: p.order_id,
    orderDisplayId: p.order_display_id,
    deliveryId: p.delivery_id,
    status: p.status,
    restaurante: p.restaurante_nome ?? null,
    restauranteUid: p.restaurante_uid ?? null,
    cliente: p.customer_name,
    endereco: p.delivery_address,
    formaPagamento: p.payment_method,
    tipoPagamento: p.payment_type,
    valorPedido: (p.order_total_cents ?? 0) / 100,
    taxaMotoboy: (p.delivery_fee_cents ?? 0) / 100,
    observacoes: p.observacoes,
    motoboyUid: p.motoboy_uid,
    confirmationCodeRequired: p.confirmation_code_required === 1,
    codigoConfirmado: p.codigo_confirmado === 1,
    criadoEm: p.criado_em,
    atualizadoEm: p.atualizado_em,
  };
}
