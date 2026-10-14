import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";
import { pedidoParaJson, type PedidoRow } from "../lib/pedidoView";
import { enviarEventoDeStatus } from "../lib/saiposClient";
import type { Loja } from "../lib/partnerAuth";

export const deliveriesRejeitar = new Hono<{ Bindings: Env }>();

// POST /api/deliveries/:id/rejeitar — motoboy recusa uma entrega que ainda
// não aceitou (ex.: não consegue atender agora). Só funciona em pedidos
// DISPONIVEL — depois de aceitar, o caminho correto é finalizar ou (se
// formos implementar no futuro) cancelar já em andamento.
deliveriesRejeitar.post("/:id/rejeitar", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  const body = await c.req.json<{ motivo?: string }>().catch(() => ({}) as { motivo?: string });

  const pedido = await c.env.DB
    .prepare(
      `SELECT p.*, l.nome AS restaurante_nome, l.restaurante_uid, l.id AS loja_id, l.merchant_id, l.client_id, l.client_secret, l.ambiente
       FROM pedidos p
       JOIN lojas l ON l.id = p.loja_id AND l.motoboy_uid = ?
       WHERE p.id = ?`,
    )
    .bind(motoboy.uid, id)
    .first<PedidoRow & Loja & { loja_id: number }>();

  if (!pedido) return c.json({ error: "not_found" }, 404);
  if (pedido.status !== "DISPONIVEL") {
    return c.json({ error: "invalid_state", error_description: "Pedido não está mais disponível pra recusar" }, 400);
  }

  await c.env.DB
    .prepare("UPDATE pedidos SET status = 'REJEITADA', atualizado_em = datetime('now') WHERE id = ?")
    .bind(id)
    .run();

  await enviarEventoDeStatus({
    loja: { id: pedido.loja_id, merchant_id: pedido.merchant_id, nome: pedido.restaurante_nome ?? "", client_id: pedido.client_id, client_secret: pedido.client_secret, motoboy_uid: motoboy.uid, ambiente: pedido.ambiente },
    appId: c.env.SAIPOS_APP_ID,
    deliveryId: pedido.delivery_id,
    orderId: pedido.order_id,
    orderDisplayId: pedido.order_display_id,
    customerName: pedido.customer_name,
    event: "REJECTED",
    message: body.motivo,
  });

  return c.json({ ...pedidoParaJson(pedido), status: "REJEITADA" }, 200);
});
