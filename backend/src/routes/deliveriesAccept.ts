import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";
import { aceitarPedido } from "../lib/aceitarPedido";

export const deliveriesAccept = new Hono<{ Bindings: Env }>();

// POST /api/deliveries/:id/accept — aceite explícito por id. Hoje o fluxo
// principal é o scan (que já aceita automaticamente, ver
// routes/deliveriesScan.ts), mas esse endpoint continua disponível como
// caminho alternativo/retry.
deliveriesAccept.post("/:id/accept", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  // Confere que o motoboy é o dono do registro de entregador dessa loja
  // antes de tentar aceitar (ver routes/deliveriesScan.ts pro contexto do
  // modelo por entregador individual).
  const autorizado = await c.env.DB
    .prepare(
      `SELECT 1 FROM pedidos p
       JOIN lojas l ON l.id = p.loja_id AND l.motoboy_uid = ?
       WHERE p.id = ?`,
    )
    .bind(motoboy.uid, id)
    .first();
  if (!autorizado) return c.json({ error: "not_found" }, 404);

  const body = await c.req
    .json<{ nome?: string; telefone?: string }>()
    .catch(() => ({}) as { nome?: string; telefone?: string });

  const resultado = await aceitarPedido(c.env.DB, c.env.SAIPOS_APP_ID, id, motoboy.uid, body.nome, body.telefone);

  if (resultado.resultado === "already_taken") {
    return c.json({ error: "already_taken", error_description: "Pedido já foi aceito por outro motoboy" }, 409);
  }
  if (resultado.resultado === "not_found") {
    return c.json({ error: "not_found" }, 404);
  }
  return c.json(resultado.pedido, 200);
});
