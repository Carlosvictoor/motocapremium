import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";
import { pedidoParaJson, type PedidoRow } from "../lib/pedidoView";

export const deliveriesList = new Hono<{ Bindings: Env }>();

// GET /api/deliveries — lista os pedidos desse motoboy: os que ele já
// escaneou/aceitou (ACEITA/RETIRADA/EM_ENTREGA) e também os que já nasceram
// atribuídos a ele (DISPONIVEL com motoboy_uid dele, ver
// routes/logisticsDelivery.ts) — esses aparecem com botão "Aceitar" no app,
// sem precisar escanear a comanda física. Pedidos DISPONIVEL sem motoboy_uid
// (nenhum ainda, mas mantido como caminho de fallback) continuam invisíveis
// aqui até serem escaneados (ver routes/deliveriesScan.ts). O total de taxas
// é somado aqui no backend (nunca no Flutter).
deliveriesList.get("/", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const { results } = await c.env.DB
    .prepare(
      `SELECT p.*, l.nome AS restaurante_nome, l.restaurante_uid FROM pedidos p
       JOIN lojas l ON l.id = p.loja_id
       WHERE p.motoboy_uid = ? AND p.status IN ('DISPONIVEL','ACEITA','RETIRADA','EM_ENTREGA')
       ORDER BY p.criado_em DESC`,
    )
    .bind(motoboy.uid)
    .all<PedidoRow>();

  const totalTaxasCentavos = await c.env.DB
    .prepare(
      `SELECT COALESCE(SUM(delivery_fee_cents), 0) AS total FROM pedidos
       WHERE motoboy_uid = ? AND status IN ('ACEITA','RETIRADA','EM_ENTREGA')`,
    )
    .bind(motoboy.uid)
    .first<{ total: number }>();

  return c.json(
    {
      pedidos: results.map(pedidoParaJson),
      totalTaxas: (totalTaxasCentavos?.total ?? 0) / 100,
    },
    200,
  );
});
