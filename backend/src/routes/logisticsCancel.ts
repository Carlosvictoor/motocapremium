import { Hono } from "hono";
import type { Env } from "../index";
import { validarToken } from "../lib/partnerAuth";
import { enviarEventoDeStatus } from "../lib/saiposClient";

export const logisticsCancel = new Hono<{ Bindings: Env }>();

// POST /v1/logistics/cancel/:orderId — chamado PELA SAIPOS pra pedir o
// cancelamento de uma entrega já solicitada. A doc oficial da Saipos confirma
// que esse endpoint deve ser disponibilizado pelo parceiro, mas não detalha o
// formato exato da resposta esperada (TODO confirmar com o suporte antes da
// homologação) — por ora respondemos 200 com o status atualizado, seguindo o
// padrão dos demais endpoints /v1/logistics/*.
logisticsCancel.post("/:orderId", async (c) => {
  const loja = await validarToken(c.env.DB, c.req.header("authorization") ?? null);
  if (!loja) return c.json({ error: "unauthorized" }, 401);

  const orderId = c.req.param("orderId");
  const pedido = await c.env.DB
    .prepare("SELECT id, delivery_id, order_display_id, customer_name, status FROM pedidos WHERE loja_id = ? AND order_id = ?")
    .bind(loja.id, orderId)
    .first<{ id: number; delivery_id: string; order_display_id: string | null; customer_name: string | null; status: string }>();

  if (!pedido) return c.json({ error: "not_found" }, 404);

  // Idempotente: se já estava cancelada, só confirma de novo sem reenviar evento.
  if (pedido.status !== "CANCELADA") {
    await c.env.DB
      .prepare("UPDATE pedidos SET status = 'CANCELADA', atualizado_em = datetime('now') WHERE id = ?")
      .bind(pedido.id)
      .run();

    await enviarEventoDeStatus({
      loja,
      appId: c.env.SAIPOS_APP_ID,
      deliveryId: pedido.delivery_id,
      orderId,
      orderDisplayId: pedido.order_display_id,
      customerName: pedido.customer_name,
      event: "CANCELLED",
      message: "Cancelado a pedido da loja.",
    });
  }

  return c.json({ deliveryId: pedido.delivery_id, event: "CANCELLED" }, 200);
});
