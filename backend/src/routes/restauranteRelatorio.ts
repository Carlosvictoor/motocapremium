// Relatório do painel do restaurante (Fase 12): quantas saídas, quais
// comandas e quanto cada motoboy ganhou entregando pra esse restaurante.
// 100% derivado do D1 (pedidos Saipos ENTREGUE + entregas externas
// finalizadas) — não depende de saber quem está "vinculado" no Firestore,
// só agrupa por motoboy_uid quem aparece nas próprias entregas. O corte de
// "hoje" por motoboy usa o mais recente entre dois sinais: o motoboy
// apertando "Zerar o dia" no Financeiro dele (motoboy_zerado_em, ver
// motoboyZerarDia.ts) OU o restaurante apertando "Zerar o dia" manual
// aqui na aba Relatório (restaurante_motoboy_zerado_em, Fase 12.1) — o que
// acontecer por último fecha o período aberto atual. Um motoboy só entra
// na lista "Por motoboy" enquanto tiver pelo menos uma entrega no período
// aberto atual (Fase 12.2) — depois de zerar, ele some da lista até
// escanear/finalizar de novo.
import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";

export const restauranteRelatorio = new Hono<{ Bindings: Env }>();

type MetodoPagamento = "credito" | "debito" | "cartao" | "dinheiro" | "pix" | "outros";

interface LinhaEntrega {
  motoboyUid: string;
  referencia: string;
  taxaCents: number;
  valorVendaCents: number;
  metodoPagamento: MetodoPagamento;
  data: string;
}

/// Saipos manda o tipo de pagamento estruturado (CREDIT/DEBIT/PIX/CASH/...) —
/// dá pra separar crédito de débito direto. "CREDIT_DEBIT" existe no schema
/// da Saipos pra quando ela mesma não sabe qual dos dois foi (maquininha
/// genérica) — cai no bucket "cartao" (não especificado), não é erro nem
/// heurística, é a própria Saipos não distinguindo. Integrações externas só
/// mandam texto livre (ex.: "ONLINE (PAGO)") — nesse caso é heurística por
/// substring (mesmo padrão já usado pro getter `pago` de EntregaExterna no
/// Flutter), não é garantido 100%.
function bucketPagamento(paymentType: string | null, formaPagamentoTexto: string | null): MetodoPagamento {
  if (paymentType) {
    if (paymentType === "CREDIT") return "credito";
    if (paymentType === "DEBIT") return "debito";
    if (paymentType === "CREDIT_DEBIT") return "cartao";
    if (paymentType === "CASH") return "dinheiro";
    if (paymentType === "PIX") return "pix";
    return "outros";
  }
  const texto = (formaPagamentoTexto ?? "").toLowerCase();
  if (texto.includes("pix")) return "pix";
  if (texto.includes("dinheiro") || texto.includes("cash") || texto.includes("especie")) return "dinheiro";
  if (texto.includes("credit")) return "credito";
  if (texto.includes("debit")) return "debito";
  if (texto.includes("cart") || texto.includes("card")) return "cartao";
  return "outros";
}

restauranteRelatorio.get("/", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const { results: lojas } = await c.env.DB
    .prepare("SELECT id FROM lojas WHERE restaurante_uid = ?")
    .bind(restaurante.uid)
    .all<{ id: number }>();
  const { results: integracoes } = await c.env.DB
    .prepare("SELECT id FROM integracoes_externas WHERE restaurante_uid = ?")
    .bind(restaurante.uid)
    .all<{ id: number }>();

  const lojaIds = lojas.map((l) => l.id);
  const integracaoIds = integracoes.map((i) => i.id);

  const linhas: LinhaEntrega[] = [];

  if (lojaIds.length > 0) {
    const placeholders = lojaIds.map(() => "?").join(",");
    const { results } = await c.env.DB
      .prepare(
        `SELECT motoboy_uid, COALESCE(order_display_id, order_id) AS referencia,
                COALESCE(delivery_fee_final_cents, delivery_fee_cents, 0) AS taxa_cents,
                COALESCE(order_total_cents, 0) AS valor_venda_cents,
                payment_type,
                atualizado_em AS data
         FROM pedidos
         WHERE loja_id IN (${placeholders}) AND status = 'ENTREGUE' AND motoboy_uid IS NOT NULL`,
      )
      .bind(...lojaIds)
      .all<{ motoboy_uid: string; referencia: string; taxa_cents: number; valor_venda_cents: number; payment_type: string | null; data: string }>();
    for (const r of results) {
      linhas.push({
        motoboyUid: r.motoboy_uid,
        referencia: r.referencia,
        taxaCents: r.taxa_cents,
        valorVendaCents: r.valor_venda_cents,
        metodoPagamento: bucketPagamento(r.payment_type, null),
        data: r.data,
      });
    }
  }

  if (integracaoIds.length > 0) {
    const placeholders = integracaoIds.map(() => "?").join(",");
    const { results } = await c.env.DB
      .prepare(
        `SELECT motoboy_uid, pedido AS referencia, taxa_cents,
                valor_total_cents AS valor_venda_cents, forma_pagamento, criado_em AS data
         FROM entregas_externas_finalizadas
         WHERE integracao_id IN (${placeholders})`,
      )
      .bind(...integracaoIds)
      .all<{ motoboy_uid: string; referencia: string; taxa_cents: number; valor_venda_cents: number; forma_pagamento: string | null; data: string }>();
    for (const r of results) {
      linhas.push({
        motoboyUid: r.motoboy_uid,
        referencia: r.referencia,
        taxaCents: r.taxa_cents,
        valorVendaCents: r.valor_venda_cents,
        metodoPagamento: bucketPagamento(null, r.forma_pagamento),
        data: r.data,
      });
    }
  }

  const motoboyUids = [...new Set(linhas.map((l) => l.motoboyUid))];
  const zeradoMap = new Map<string, string>();
  if (motoboyUids.length > 0) {
    const placeholders = motoboyUids.map(() => "?").join(",");
    const { results } = await c.env.DB
      .prepare(`SELECT motoboy_uid, zerado_em FROM motoboy_zerado_em WHERE motoboy_uid IN (${placeholders})`)
      .bind(...motoboyUids)
      .all<{ motoboy_uid: string; zerado_em: string }>();
    for (const r of results) zeradoMap.set(r.motoboy_uid, r.zerado_em);

    const { results: resultsRestaurante } = await c.env.DB
      .prepare(
        `SELECT motoboy_uid, zerado_em FROM restaurante_motoboy_zerado_em
         WHERE restaurante_uid = ? AND motoboy_uid IN (${placeholders})`,
      )
      .bind(restaurante.uid, ...motoboyUids)
      .all<{ motoboy_uid: string; zerado_em: string }>();
    for (const r of resultsRestaurante) {
      const atual = zeradoMap.get(r.motoboy_uid);
      if (!atual || r.zerado_em > atual) zeradoMap.set(r.motoboy_uid, r.zerado_em);
    }
  }

  // Corte padrão pra quem nunca zerou o dia: meia-noite (UTC) de hoje —
  // evita mostrar meses de histórico como "hoje" logo no primeiro vínculo.
  const inicioHojeIso = `${new Date().toISOString().slice(0, 10)} 00:00:00`;

  const porMotoboy = new Map<string, LinhaEntrega[]>();
  for (const linha of linhas) {
    const grupo = porMotoboy.get(linha.motoboyUid) ?? [];
    grupo.push(linha);
    porMotoboy.set(linha.motoboyUid, grupo);
  }

  const linhasHoje: LinhaEntrega[] = [];

  const motoboys = [...porMotoboy.entries()]
    .map(([motoboyUid, todas]) => {
      const cutoff = zeradoMap.get(motoboyUid) ?? inicioHojeIso;
      const hoje = todas.filter((l) => l.data > cutoff);
      linhasHoje.push(...hoje);
      return {
        motoboyUid,
        hoje: {
          saidas: hoje.length,
          totalCents: hoje.reduce((s, l) => s + l.taxaCents, 0),
          comandas: hoje.map((l) => ({ referencia: l.referencia, taxaCents: l.taxaCents, data: l.data })),
        },
        historicoSaidas: todas.length,
        historicoTotalCents: todas.reduce((s, l) => s + l.taxaCents, 0),
      };
    })
    // Depois de zerar, um motoboy sem entrega no período aberto atual some
    // da lista até escanear/finalizar de novo (Fase 12.2) — o histórico
    // continua contando pra sempre no banco, só não aparece aqui enquanto
    // "hoje" estiver vazio.
    .filter((m) => m.hoje.saidas > 0);

  const somaPorMetodo = (metodo: MetodoPagamento) =>
    linhasHoje.filter((l) => l.metodoPagamento === metodo).reduce((s, l) => s + l.valorVendaCents, 0);

  const totalHojeCents = motoboys.reduce((s, m) => s + m.hoje.totalCents, 0);
  const totalHojeSaidas = motoboys.reduce((s, m) => s + m.hoje.saidas, 0);
  const totalVendasCents = linhasHoje.reduce((s, l) => s + l.valorVendaCents, 0);
  const totalCreditoCents = somaPorMetodo("credito");
  const totalDebitoCents = somaPorMetodo("debito");
  const totalCartaoCents = somaPorMetodo("cartao");
  const totalDinheiroCents = somaPorMetodo("dinheiro");
  const totalPixCents = somaPorMetodo("pix");
  const totalOutrosCents = somaPorMetodo("outros");

  return c.json(
    {
      motoboys,
      totalHojeCents,
      totalHojeSaidas,
      totalVendasCents,
      totalCreditoCents,
      totalDebitoCents,
      totalCartaoCents,
      totalDinheiroCents,
      totalPixCents,
      totalOutrosCents,
    },
    200,
  );
});

// POST /api/restaurante/relatorio/zerar/:motoboyUid — o restaurante zera
// manualmente o período "hoje" desse motoboy no relatório dele (Fase
// 12.1), sem precisar esperar o motoboy apertar o próprio botão no
// Financeiro. Escopado por (restaurante, motoboy): não mexe no corte
// desse motoboy em nenhum outro restaurante que ele também atenda.
restauranteRelatorio.post("/zerar/:motoboyUid", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const motoboyUid = c.req.param("motoboyUid");
  if (!motoboyUid) return c.json({ error: "invalid_request" }, 400);

  await c.env.DB
    .prepare(
      `INSERT INTO restaurante_motoboy_zerado_em (restaurante_uid, motoboy_uid, zerado_em) VALUES (?, ?, datetime('now'))
       ON CONFLICT (restaurante_uid, motoboy_uid) DO UPDATE SET zerado_em = excluded.zerado_em`,
    )
    .bind(restaurante.uid, motoboyUid)
    .run();

  return c.json({ ok: true }, 200);
});
