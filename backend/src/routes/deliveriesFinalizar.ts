import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";
import { pedidoParaJson, type PedidoRow } from "../lib/pedidoView";
import { enviarEventoDeStatus } from "../lib/saiposClient";
import type { Loja } from "../lib/partnerAuth";

export const deliveriesFinalizar = new Hono<{ Bindings: Env }>();

// POST /api/deliveries/:id/finalizar — chamado PELO FLUTTER quando o
// motoboy toca em "Finalizar entrega". Se o pedido exige código de
// confirmação, exige que /confirmar-codigo já tenha sido chamado com
// sucesso antes (codigo_confirmado = 1) — não confia em nada que o app
// disser sobre isso, confere direto no banco.
deliveriesFinalizar.post("/:id/finalizar", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  const pedido = await c.env.DB
    .prepare(
      `SELECT p.*, l.nome AS restaurante_nome, l.restaurante_uid, l.id AS loja_id, l.merchant_id, l.client_id, l.client_secret, l.ambiente
       FROM pedidos p
       JOIN lojas l ON l.id = p.loja_id AND l.motoboy_uid = ?
       WHERE p.id = ? AND p.motoboy_uid = ?`,
    )
    .bind(motoboy.uid, id, motoboy.uid)
    .first<PedidoRow & Loja & { loja_id: number }>();

  if (!pedido) return c.json({ error: "not_found" }, 404);
  if (pedido.status !== "ACEITA") {
    return c.json({ error: "invalid_state", error_description: "Pedido não está aceito" }, 400);
  }
  if (pedido.confirmation_code_required === 1 && pedido.codigo_confirmado !== 1) {
    return c.json({ error: "code_required", error_description: "Confirme o código de entrega antes de finalizar" }, 400);
  }

  // Taxa efetiva (Fase 12) — só quando o app manda um valor diferente do
  // original (restaurante com sobreposição por bairro ligada, Fase 11.1).
  // Isso só alimenta o relatório interno do restaurante; o evento mandado
  // pra Saipos logo abaixo continua usando delivery_fee_cents original,
  // sem mudar nada da contabilidade combinada com eles.
  const body = await c.req.json<{ taxaEfetivaCents?: number }>().catch(() => ({}) as { taxaEfetivaCents?: number });
  const taxaEfetivaCents =
    typeof body.taxaEfetivaCents === "number" && body.taxaEfetivaCents !== pedido.delivery_fee_cents
      ? body.taxaEfetivaCents
      : null;

  await c.env.DB
    .prepare("UPDATE pedidos SET status = 'ENTREGUE', atualizado_em = datetime('now'), delivery_fee_final_cents = ? WHERE id = ?")
    .bind(taxaEfetivaCents, id)
    .run();

  await enviarEventoDeStatus({
    loja: { id: pedido.loja_id, merchant_id: pedido.merchant_id, nome: pedido.restaurante_nome ?? "", client_id: pedido.client_id, client_secret: pedido.client_secret, motoboy_uid: motoboy.uid, ambiente: pedido.ambiente },
    appId: c.env.SAIPOS_APP_ID,
    deliveryId: pedido.delivery_id,
    orderId: pedido.order_id,
    orderDisplayId: pedido.order_display_id,
    customerName: pedido.customer_name,
    event: "DELIVERY_FINISHED",
    deliveryFeeCents: pedido.delivery_fee_cents ?? 0,
    motoboyUid: motoboy.uid,
  });

  return c.json({ ...pedidoParaJson(pedido), status: "ENTREGUE" }, 200);
});
