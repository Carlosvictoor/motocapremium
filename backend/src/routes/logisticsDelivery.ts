import { Hono } from "hono";
import type { Env } from "../index";
import { validarToken } from "../lib/partnerAuth";
import type { DeliveryOrderPayload } from "../lib/openDeliveryTypes";
import { formatarEndereco } from "../lib/openDeliveryTypes";

export const logisticsDelivery = new Hono<{ Bindings: Env }>();

// POST /v1/logistics/delivery — chamado PELA SAIPOS pra solicitar uma nova
// entrega. Contrato (método, campos obrigatórios, resposta 202 com
// deliveryId/event/completion) confirmado no schema oficial DeliveryOrder /
// DeliveryOrderResponse. Precisa responder em até 10s (exigência da Saipos).
logisticsDelivery.post("/", async (c) => {
  const loja = await validarToken(c.env.DB, c.req.header("authorization") ?? null);
  if (!loja) return c.json({ error: "unauthorized" }, 401);

  const payload = await c.req.json<DeliveryOrderPayload>().catch(() => null);
  if (!payload?.orderId || !payload.merchant?.id) {
    return c.json({ error: "invalid_request" }, 400);
  }

  // Isolamento multi-restaurante: o token só pode criar pedidos pra loja
  // dona daquele client_id/client_secret, nunca pra outro merchant.
  if (payload.merchant.id !== loja.merchant_id) {
    return c.json({ error: "access_denied", error_description: "merchant.id não pertence a este token" }, 403);
  }

  // Idempotência: se a Saipos reenviar o mesmo orderId (retry), não duplica —
  // devolve o deliveryId já gerado da primeira vez.
  const existente = await c.env.DB
    .prepare("SELECT delivery_id FROM pedidos WHERE loja_id = ? AND order_id = ?")
    .bind(loja.id, payload.orderId)
    .first<{ delivery_id: string }>();

  if (existente) {
    return c.json(
      {
        deliveryId: existente.delivery_id,
        event: "PENDING",
        completion: {
          estimate: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
          rejectAfter: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
        },
      },
      202,
    );
  }

  const deliveryId = crypto.randomUUID();
  const pagamento = payload.payments;
  const offline = pagamento?.offlineMethod?.[0];

  // Cada loja (registro de entregador) já pertence a um único motoboy desde
  // o cadastro (motoboy_uid obrigatório em restauranteLojas.ts) — grava isso
  // no pedido já na criação (status continua DISPONIVEL até ele aceitar) pra
  // ele aparecer direto na lista dele (ver deliveriesList.ts) sem precisar
  // escanear a comanda física.

  await c.env.DB
    .prepare(
      `INSERT INTO pedidos (
        loja_id, order_id, order_display_id, delivery_id, status,
        customer_name, delivery_address, payment_method, payment_type,
        order_total_cents, delivery_fee_cents, observacoes,
        confirmation_code_required, payload_raw, motoboy_uid
      ) VALUES (?, ?, ?, ?, 'DISPONIVEL', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      loja.id,
      payload.orderId,
      payload.orderDisplayId ?? null,
      deliveryId,
      payload.customerName ?? null,
      formatarEndereco(payload.deliveryAddress),
      pagamento?.method ?? null,
      offline?.type ?? null,
      Math.round((payload.totalOrderPrice?.value ?? 0) * 100),
      Math.round((payload.orderDeliveryFee?.value ?? 0) * 100),
      payload.specialInstructions ?? null,
      payload.confirmationCodeRequired ? 1 : 0,
      JSON.stringify(payload),
      loja.motoboy_uid,
    )
    .run();

  return c.json(
    {
      deliveryId,
      event: "PENDING",
      completion: {
        estimate: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
        rejectAfter: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      },
    },
    202,
  );
});
