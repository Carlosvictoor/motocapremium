import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";
import { pedidoParaJson, type PedidoRow } from "../lib/pedidoView";
import { aceitarPedido } from "../lib/aceitarPedido";

export const deliveriesScan = new Hono<{ Bindings: Env }>();

// POST /api/deliveries/scan — chamado PELO FLUTTER depois de ler o código de
// barras com a câmera. Busca o valor lido em order_display_id (candidato
// principal) e, como reforço, em order_id — só dentro das lojas cujo
// registro de entregador (lojas.motoboy_uid) pertence a esse motoboy.
//
// Modelo confirmado na tela real da Saipos: cada linha de `lojas` é um
// registro de UM entregador específico num restaurante (Merchant ID gerado
// por lá é por entregador, não por restaurante) — então só o motoboy dono
// daquele registro consegue ver/escanear pedidos dele. Não existe mais
// "vários motoboys disputando o mesmo pedido".
deliveriesScan.post("/", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const body = await c.req.json<{ barcode?: string; nome?: string; telefone?: string }>().catch(() => null);
  const barcode = body?.barcode?.trim();
  if (!barcode) return c.json({ error: "invalid_request", error_description: "barcode é obrigatório" }, 400);

  const pedido = await c.env.DB
    .prepare(
      `SELECT p.*, l.nome AS restaurante_nome, l.restaurante_uid FROM pedidos p
       JOIN lojas l ON l.id = p.loja_id
       WHERE l.motoboy_uid = ? AND (p.order_display_id = ? OR p.order_id = ?)
       ORDER BY p.criado_em DESC
       LIMIT 1`,
    )
    .bind(motoboy.uid, barcode, barcode)
    .first<PedidoRow>();

  if (!pedido) return c.json({ error: "not_found" }, 404);

  // Já é desse motoboy (escaneou de novo o mesmo cupom, ex.: pra reabrir o
  // card) — devolve como está, sem tentar aceitar de novo.
  if (pedido.status !== "DISPONIVEL" && pedido.motoboy_uid === motoboy.uid) {
    return c.json(pedidoParaJson(pedido), 200);
  }
  if (pedido.status !== "DISPONIVEL") {
    return c.json({ error: "already_taken", error_description: "Pedido já foi aceito por outro motoboy" }, 409);
  }

  const resultado = await aceitarPedido(c.env.DB, c.env.SAIPOS_APP_ID, pedido.id, motoboy.uid, body?.nome, body?.telefone);

  if (resultado.resultado === "already_taken") {
    return c.json({ error: "already_taken", error_description: "Pedido já foi aceito por outro motoboy" }, 409);
  }
  if (resultado.resultado === "not_found") {
    return c.json({ error: "not_found" }, 404);
  }

  // Escanear UM pedido já aceita de uma vez todos os outros que estiverem
  // disponíveis pra esse motoboy — como cada loja é exclusiva de um único
  // entregador (Merchant ID por entregador, não por restaurante), qualquer
  // pedido disponível ali já é dele mesmo antes de escanear; isso evita ter
  // que escanear recibo por recibo quando pega várias entregas de uma vez.
  const outros = await c.env.DB
    .prepare(
      `SELECT p.id FROM pedidos p
       JOIN lojas l ON l.id = p.loja_id
       WHERE l.motoboy_uid = ? AND p.status = 'DISPONIVEL' AND p.id != ?`,
    )
    .bind(motoboy.uid, pedido.id)
    .all<{ id: number }>();

  for (const row of outros.results) {
    try {
      await aceitarPedido(c.env.DB, c.env.SAIPOS_APP_ID, row.id, motoboy.uid, body?.nome, body?.telefone);
    } catch (e) {
      // Um pedido falhando aqui não deve derrubar a resposta do scan
      // principal, que já foi aceito com sucesso — só loga e segue.
      console.log("DEBUG falha ao auto-aceitar pedido", row.id, ":", e instanceof Error ? e.message : e);
    }
  }

  return c.json(resultado.pedido, 200);
});
