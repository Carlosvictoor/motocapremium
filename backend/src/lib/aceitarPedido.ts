// Lógica compartilhada de "aceitar um pedido" — usada tanto pelo endpoint
// de aceite explícito quanto pelo scan (que agora aceita automaticamente
// assim que acha o pedido, ver routes/deliveriesScan.ts).
//
// Concorrência: o UPDATE só é aplicado se o pedido ainda estiver DISPONIVEL;
// D1 executa essa escrita de forma atômica, então se dois motoboys chamarem
// ao mesmo tempo só um dos UPDATEs afeta a linha.

import { pedidoParaJson, type PedidoRow } from "./pedidoView";
import { enviarEventoDeStatus } from "./saiposClient";
import type { Loja } from "./partnerAuth";

type ResultadoAceite =
  | { resultado: "ok"; pedido: ReturnType<typeof pedidoParaJson> }
  | { resultado: "already_taken" }
  | { resultado: "not_found" };

export async function aceitarPedido(
  db: D1Database,
  appId: string,
  pedidoId: number,
  motoboyUid: string,
  motoboyNome?: string,
  motoboyTelefone?: string,
): Promise<ResultadoAceite> {
  const resultado = await db
    .prepare(
      `UPDATE pedidos SET status = 'ACEITA', motoboy_uid = ?, atualizado_em = datetime('now')
       WHERE id = ? AND status = 'DISPONIVEL'`,
    )
    .bind(motoboyUid, pedidoId)
    .run();

  if (resultado.meta.changes === 0) {
    return { resultado: "already_taken" };
  }

  const pedido = await db
    .prepare(
      `SELECT p.*, l.nome AS restaurante_nome, l.restaurante_uid, l.id AS loja_id, l.merchant_id, l.client_id, l.client_secret, l.ambiente
       FROM pedidos p JOIN lojas l ON l.id = p.loja_id WHERE p.id = ?`,
    )
    .bind(pedidoId)
    .first<PedidoRow & Loja & { loja_id: number }>();

  if (!pedido) return { resultado: "not_found" };

  const loja: Loja = { id: pedido.loja_id, merchant_id: pedido.merchant_id, nome: pedido.restaurante_nome ?? "", client_id: pedido.client_id, client_secret: pedido.client_secret, motoboy_uid: pedido.motoboy_uid, ambiente: pedido.ambiente };
  const baseEvento = {
    loja,
    appId,
    deliveryId: pedido.delivery_id,
    orderId: pedido.order_id,
    orderDisplayId: pedido.order_display_id,
    customerName: pedido.customer_name,
    deliveryFeeCents: pedido.delivery_fee_cents ?? 0,
    motoboyUid,
    motoboyNome,
    motoboyTelefone,
  };

  await enviarEventoDeStatus({ ...baseEvento, event: "ACCEPTED" });
  // Nosso app não tem um passo separado de "retirei no restaurante" — o
  // motoboy só aceita e depois finaliza. Pra o pedido pular direto pra
  // "Em entrega" no painel da Saipos (em vez de ficar parado em "Aguardando
  // Entrega" até finalizar), mandamos o evento de "a caminho" na sequência.
  await enviarEventoDeStatus({ ...baseEvento, event: "DELIVERY_ONGOING" });

  return { resultado: "ok", pedido: pedidoParaJson(pedido) };
}
