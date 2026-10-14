// Aba "Financeiro" do painel do restaurante (Fase 13): histórico dia a
// dia de vendas/crédito/débito/dinheiro/pix, pro gráfico. Mesma fonte de
// dados que routes/restauranteRelatorio.ts (pedidos ENTREGUE + entregas
// externas finalizadas) — os dados brutos nunca são apagados. "Meses
// fechados" (Fase 13.4) congela um snapshot dos totais de cada mês em
// restaurante_fechamentos e move o corte do período "atual" pra frente —
// é isso que "zera" os números da tela, sem apagar nada do histórico.
// O fechamento por mês agora é AUTOMÁTICO: toda vez que GET / é chamado
// (o app chama isso sempre que a aba Financeiro abre), confere se o
// calendário virou o mês desde o último corte e, se sim, fecha o mês
// anterior sozinho antes de responder — sem precisar de botão manual.
import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";

export const restauranteFinanceiro = new Hono<{ Bindings: Env }>();

type MetodoPagamento = "credito" | "debito" | "cartao" | "dinheiro" | "pix" | "outros";

interface Linha {
  data: string; // YYYY-MM-DD HH:MM:SS
  taxaCents: number;
  valorVendaCents: number;
  metodoPagamento: MetodoPagamento;
}

/// "CREDIT_DEBIT" existe no schema da Saipos pra quando ela mesma não sabe
/// qual dos dois foi (maquininha genérica) — cai em "cartao" (não
/// especificado). Ver mesma função em restauranteRelatorio.ts.
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

function agoraSql(): string {
  return new Date().toISOString().slice(0, 19).replace("T", " ");
}

/// Busca todas as linhas (pedidos Saipos ENTREGUE + entregas externas
/// finalizadas) desse restaurante desde [desde] (inclusive) até [ate]
/// (exclusive, se informado) — comparação textual, funciona tanto com
/// uma data "YYYY-MM-DD" quanto um datetime completo.
async function buscarLinhas(db: D1Database, restauranteUid: string, desde: string, ate?: string): Promise<Linha[]> {
  const { results: lojas } = await db.prepare("SELECT id FROM lojas WHERE restaurante_uid = ?").bind(restauranteUid).all<{ id: number }>();
  const { results: integracoes } = await db
    .prepare("SELECT id FROM integracoes_externas WHERE restaurante_uid = ?")
    .bind(restauranteUid)
    .all<{ id: number }>();

  const lojaIds = lojas.map((l) => l.id);
  const integracaoIds = integracoes.map((i) => i.id);
  const linhas: Linha[] = [];

  if (lojaIds.length > 0) {
    const placeholders = lojaIds.map(() => "?").join(",");
    const binds: unknown[] = [...lojaIds, desde];
    let sql = `SELECT atualizado_em AS data,
                COALESCE(delivery_fee_final_cents, delivery_fee_cents, 0) AS taxa_cents,
                COALESCE(order_total_cents, 0) AS valor_venda_cents,
                payment_type
         FROM pedidos
         WHERE loja_id IN (${placeholders}) AND status = 'ENTREGUE' AND atualizado_em >= ?`;
    if (ate) {
      sql += " AND atualizado_em < ?";
      binds.push(ate);
    }
    const { results } = await db
      .prepare(sql)
      .bind(...binds)
      .all<{ data: string; taxa_cents: number; valor_venda_cents: number; payment_type: string | null }>();
    for (const r of results) {
      linhas.push({ data: r.data, taxaCents: r.taxa_cents, valorVendaCents: r.valor_venda_cents, metodoPagamento: bucketPagamento(r.payment_type, null) });
    }
  }

  if (integracaoIds.length > 0) {
    const placeholders = integracaoIds.map(() => "?").join(",");
    const binds: unknown[] = [...integracaoIds, desde];
    let sql = `SELECT criado_em AS data, taxa_cents,
                valor_total_cents AS valor_venda_cents, forma_pagamento
         FROM entregas_externas_finalizadas
         WHERE integracao_id IN (${placeholders}) AND criado_em >= ?`;
    if (ate) {
      sql += " AND criado_em < ?";
      binds.push(ate);
    }
    const { results } = await db
      .prepare(sql)
      .bind(...binds)
      .all<{ data: string; taxa_cents: number; valor_venda_cents: number; forma_pagamento: string | null }>();
    for (const r of results) {
      linhas.push({ data: r.data, taxaCents: r.taxa_cents, valorVendaCents: r.valor_venda_cents, metodoPagamento: bucketPagamento(null, r.forma_pagamento) });
    }
  }

  return linhas;
}

async function ultimoFechamento(db: D1Database, restauranteUid: string): Promise<string | null> {
  const row = await db
    .prepare("SELECT periodo_fim FROM restaurante_fechamentos WHERE restaurante_uid = ? ORDER BY periodo_fim DESC LIMIT 1")
    .bind(restauranteUid)
    .first<{ periodo_fim: string }>();
  return row?.periodo_fim ?? null;
}

/// Corte efetivo do período "atual": o mais recente entre o último
/// "Fechar mês" (mantém histórico) e o último "Zerar tudo" (não mantém —
/// ver POST /zerar-tudo). `null` se nunca fechou nem zerou.
async function ultimoCorte(db: D1Database, restauranteUid: string): Promise<string | null> {
  const fechamento = await ultimoFechamento(db, restauranteUid);
  const zerado = await db
    .prepare("SELECT zerado_em FROM restaurante_financeiro_zerado_em WHERE restaurante_uid = ?")
    .bind(restauranteUid)
    .first<{ zerado_em: string }>();
  if (!zerado) return fechamento;
  if (!fechamento) return zerado.zerado_em;
  return zerado.zerado_em > fechamento ? zerado.zerado_em : fechamento;
}

function somarPorMetodo(linhas: Linha[], metodo: MetodoPagamento): number {
  return linhas.filter((l) => l.metodoPagamento === metodo).reduce((s, l) => s + l.valorVendaCents, 0);
}

/// "YYYY-MM-01 00:00:00" do mês atual (UTC).
function inicioDoMesAtual(): string {
  const agora = new Date();
  return `${agora.getUTCFullYear()}-${String(agora.getUTCMonth() + 1).padStart(2, "0")}-01 00:00:00`;
}

/// "YYYY-MM-01 00:00:00" do mês seguinte ao mês do datetime [data].
function inicioDoMesSeguinte(data: string): string {
  const ano = Number(data.slice(0, 4));
  const mes = Number(data.slice(5, 7)); // 1-12
  const proxMes = mes === 12 ? 1 : mes + 1;
  const proxAno = mes === 12 ? ano + 1 : ano;
  return `${proxAno}-${String(proxMes).padStart(2, "0")}-01 00:00:00`;
}

async function upsertZeradoEm(db: D1Database, restauranteUid: string, zeradoEm: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO restaurante_financeiro_zerado_em (restaurante_uid, zerado_em) VALUES (?, ?)
       ON CONFLICT (restaurante_uid) DO UPDATE SET zerado_em = excluded.zerado_em`,
    )
    .bind(restauranteUid, zeradoEm)
    .run();
}

async function inserirFechamento(db: D1Database, restauranteUid: string, periodoInicio: string, periodoFim: string, linhas: Linha[]): Promise<void> {
  await db
    .prepare(
      `INSERT INTO restaurante_fechamentos (
        restaurante_uid, periodo_inicio, periodo_fim, saidas,
        total_vendas_cents, total_taxas_cents, total_credito_cents, total_debito_cents,
        total_cartao_cents, total_dinheiro_cents, total_pix_cents, total_outros_cents
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      restauranteUid,
      periodoInicio,
      periodoFim,
      linhas.length,
      linhas.reduce((s, l) => s + l.valorVendaCents, 0),
      linhas.reduce((s, l) => s + l.taxaCents, 0),
      somarPorMetodo(linhas, "credito"),
      somarPorMetodo(linhas, "debito"),
      somarPorMetodo(linhas, "cartao"),
      somarPorMetodo(linhas, "dinheiro"),
      somarPorMetodo(linhas, "pix"),
      somarPorMetodo(linhas, "outros"),
    )
    .run();
}

/// Fecha automaticamente o mês anterior se o calendário já virou desde o
/// último corte — chamado toda vez que a aba Financeiro carrega (GET /),
/// sem precisar de botão manual. Fecha só UM mês por chamada (se ficou
/// muito tempo sem abrir o app, vai se atualizando aos poucos a cada
/// carregamento, até alcançar o mês atual).
async function autoFecharSeVirouMes(db: D1Database, restauranteUid: string): Promise<void> {
  const corte = await ultimoCorte(db, restauranteUid);
  const inicioMesAtual = inicioDoMesAtual();

  if (!corte) {
    // Primeira vez que essa conta aparece aqui — estabelece o início do
    // acompanhamento a partir de agora, sem fechar nada retroativo.
    await upsertZeradoEm(db, restauranteUid, inicioMesAtual);
    return;
  }
  if (corte >= inicioMesAtual) return; // já fechado até (ou depois d)o mês atual

  const limiteProximoMes = inicioDoMesSeguinte(corte);
  const linhas = await buscarLinhas(db, restauranteUid, corte, limiteProximoMes);
  if (linhas.length > 0) {
    await inserirFechamento(db, restauranteUid, corte, limiteProximoMes, linhas);
  } else {
    // Mês sem nenhum movimento — avança o corte mesmo assim, senão fica
    // preso reprocessando o mesmo mês vazio pra sempre.
    await upsertZeradoEm(db, restauranteUid, limiteProximoMes);
  }
}

// GET /api/restaurante/financeiro?dias=30 — histórico dia a dia do
// período atual (desde o último "Mês fechado", automático — ver
// autoFecharSeVirouMes), limitado a no máximo N dias pra trás mesmo
// assim (padrão 30, máximo 90).
restauranteFinanceiro.get("/", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  await autoFecharSeVirouMes(c.env.DB, restaurante.uid);

  const diasParam = Number(c.req.query("dias"));
  const dias = Number.isInteger(diasParam) && diasParam > 0 ? Math.min(diasParam, 90) : 30;
  const limiteDias = new Date(Date.now() - dias * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const corte = await ultimoCorte(c.env.DB, restaurante.uid);
  const desde = corte && corte > limiteDias ? corte : limiteDias;

  const linhas = await buscarLinhas(c.env.DB, restaurante.uid, desde);

  const porDia = new Map<string, Linha[]>();
  for (const linha of linhas) {
    const dia = linha.data.slice(0, 10);
    const grupo = porDia.get(dia) ?? [];
    grupo.push(linha);
    porDia.set(dia, grupo);
  }

  const diasOrdenados = [...porDia.keys()].sort();
  const historico = diasOrdenados.map((data) => {
    const grupo = porDia.get(data)!;
    return {
      data,
      saidas: grupo.length,
      totalTaxasCents: grupo.reduce((s, l) => s + l.taxaCents, 0),
      totalVendasCents: grupo.reduce((s, l) => s + l.valorVendaCents, 0),
      totalCreditoCents: somarPorMetodo(grupo, "credito"),
      totalDebitoCents: somarPorMetodo(grupo, "debito"),
      totalCartaoCents: somarPorMetodo(grupo, "cartao"),
      totalDinheiroCents: somarPorMetodo(grupo, "dinheiro"),
      totalPixCents: somarPorMetodo(grupo, "pix"),
      totalOutrosCents: somarPorMetodo(grupo, "outros"),
    };
  });

  return c.json({ historico, abertoDesde: corte }, 200);
});

// POST /api/restaurante/financeiro/fechar — fecha o período atual na
// hora (não espera o mês virar). O fluxo normal agora é automático (ver
// autoFecharSeVirouMes) — essa rota fica como um fechamento manual
// avulso, sem UI própria no app hoje, mas continua funcionando.
restauranteFinanceiro.post("/fechar", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const periodoInicio = (await ultimoCorte(c.env.DB, restaurante.uid)) ?? "1970-01-01 00:00:00";
  const periodoFim = agoraSql();

  const linhas = await buscarLinhas(c.env.DB, restaurante.uid, periodoInicio);
  await inserirFechamento(c.env.DB, restaurante.uid, periodoInicio, periodoFim, linhas);

  return c.json(
    {
      periodoInicio,
      periodoFim,
      saidas: linhas.length,
      totalVendasCents: linhas.reduce((s, l) => s + l.valorVendaCents, 0),
      totalTaxasCents: linhas.reduce((s, l) => s + l.taxaCents, 0),
    },
    201,
  );
});

// GET /api/restaurante/financeiro/fechados — lista os meses já fechados
// desse restaurante, mais recente primeiro.
restauranteFinanceiro.get("/fechados", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const { results } = await c.env.DB
    .prepare(
      `SELECT id, periodo_inicio, periodo_fim, saidas, total_vendas_cents, total_taxas_cents,
              total_credito_cents, total_debito_cents, total_cartao_cents, total_dinheiro_cents,
              total_pix_cents, total_outros_cents
       FROM restaurante_fechamentos WHERE restaurante_uid = ? ORDER BY periodo_fim DESC`,
    )
    .bind(restaurante.uid)
    .all<{
      id: number;
      periodo_inicio: string;
      periodo_fim: string;
      saidas: number;
      total_vendas_cents: number;
      total_taxas_cents: number;
      total_credito_cents: number;
      total_debito_cents: number;
      total_cartao_cents: number;
      total_dinheiro_cents: number;
      total_pix_cents: number;
      total_outros_cents: number;
    }>();

  return c.json(
    {
      fechados: results.map((r) => ({
        id: r.id,
        periodoInicio: r.periodo_inicio,
        periodoFim: r.periodo_fim,
        saidas: r.saidas,
        totalVendasCents: r.total_vendas_cents,
        totalTaxasCents: r.total_taxas_cents,
        totalCreditoCents: r.total_credito_cents,
        totalDebitoCents: r.total_debito_cents,
        totalCartaoCents: r.total_cartao_cents,
        totalDinheiroCents: r.total_dinheiro_cents,
        totalPixCents: r.total_pix_cents,
        totalOutrosCents: r.total_outros_cents,
      })),
    },
    200,
  );
});

// POST /api/restaurante/financeiro/zerar-tudo — reset rápido: ao
// contrário de "Fechar mês", NÃO guarda snapshot nenhum — apaga todo o
// histórico de "Meses fechados" desse restaurante e marca o corte do
// período atual pra agora. Não apaga nenhum pedido/entrega em si (esses
// continuam no D1 pra sempre), só some com o resumo/histórico calculado.
restauranteFinanceiro.post("/zerar-tudo", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  await c.env.DB.prepare("DELETE FROM restaurante_fechamentos WHERE restaurante_uid = ?").bind(restaurante.uid).run();
  await c.env.DB
    .prepare(
      `INSERT INTO restaurante_financeiro_zerado_em (restaurante_uid, zerado_em) VALUES (?, ?)
       ON CONFLICT (restaurante_uid) DO UPDATE SET zerado_em = excluded.zerado_em`,
    )
    .bind(restaurante.uid, agoraSql())
    .run();

  return c.json({ ok: true }, 200);
});
