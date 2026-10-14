import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";
import { confirmarCodigoNaSaipos } from "../lib/saiposClient";
import type { Loja } from "../lib/partnerAuth";

export const deliveriesConfirmarCodigo = new Hono<{ Bindings: Env }>();

// POST /api/deliveries/:id/confirmar-codigo — chamado PELO FLUTTER quando o
// pedido exige código de confirmação do cliente (Saipos manda
// confirmationCodeRequired: true). Valida o código com a Saipos ANTES de
// permitir finalizar (ver routes/deliveriesFinalizar.ts).
deliveriesConfirmarCodigo.post("/:id/confirmar-codigo", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  const body = await c.req.json<{ codigo?: string }>().catch(() => ({}) as { codigo?: string });
  const codigo = body.codigo?.trim();
  if (!codigo) return c.json({ error: "invalid_request", error_description: "codigo é obrigatório" }, 400);

  const pedido = await c.env.DB
    .prepare(
      `SELECT p.id, p.order_id, p.status, p.confirmation_code_required,
              l.id AS loja_id, l.merchant_id, l.nome, l.client_id, l.client_secret, l.ambiente
       FROM pedidos p
       JOIN lojas l ON l.id = p.loja_id AND l.motoboy_uid = ?
       WHERE p.id = ?`,
    )
    .bind(motoboy.uid, id)
    .first<{ id: number; order_id: string; status: string; confirmation_code_required: number } & Loja & { loja_id: number }>();

  if (!pedido) return c.json({ error: "not_found" }, 404);
  if (pedido.status !== "ACEITA") {
    return c.json({ error: "invalid_state", error_description: "Pedido precisa estar aceito pra confirmar código" }, 400);
  }

  const resultado = await confirmarCodigoNaSaipos(
    c.env.SAIPOS_CONFIRMATION_CODE_URL,
    { id: pedido.loja_id, merchant_id: pedido.merchant_id, nome: pedido.nome, client_id: pedido.client_id, client_secret: pedido.client_secret, motoboy_uid: motoboy.uid, ambiente: pedido.ambiente },
    c.env.SAIPOS_APP_ID,
    pedido.order_id,
    codigo,
  );

  if (!resultado.configurado) {
    return c.json(
      { error: "not_configured", error_description: "A URL de validação de código da Saipos ainda não foi confirmada/configurada. Fale com o suporte deles e configure SAIPOS_CONFIRMATION_CODE_URL." },
      501,
    );
  }

  if (!resultado.valido) {
    return c.json({ error: "invalid_code", error_description: "Código incorreto." }, 400);
  }

  await c.env.DB
    .prepare("UPDATE pedidos SET codigo_confirmado = 1, atualizado_em = datetime('now') WHERE id = ?")
    .bind(id)
    .run();

  return c.json({ ok: true }, 200);
});
