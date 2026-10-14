// Integrações externas de leitura — outros sistemas de delivery (fora a
// Saipos) que um motoboy quer ver os pedidos dentro do Motoca Premium. Ao
// contrário da Saipos, aqui é só GET: a gente busca a URL cadastrada e
// devolve os pedidos formatados, sem mandar nenhum evento de volta ("as
// baixas são feitas no painel interno do sistema deles"). Cada motoboy pode
// ter zero, uma ou várias integrações cadastradas (tabela
// integracoes_externas, ver db/schema.sql).
import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";

export const integracoesExternas = new Hono<{ Bindings: Env }>();

function autorizadoAdmin(c: { req: { header(name: string): string | undefined }; env: Env }): boolean {
  const chave = c.req.header("x-admin-key");
  return !!chave && chave === c.env.ADMIN_API_KEY;
}

interface PedidoExternoBruto {
  id?: number | string;
  pedido?: string | number;
  order_id?: string | number;
  cliente?: string;
  customer?: string;
  endereco?: string;
  address?: string;
  forma_pagamento?: string;
  pagamento?: string;
  valor_cobrar?: number;
  valor?: number;
  receber?: number;
  taxa?: number;
  taxa_entrega?: number;
  status?: string;
  status_entrega?: string;
  loja?: string;
  localizador?: string;
  data_hora?: string;
}

/// Normaliza um pedido bruto do sistema externo pro formato canônico que a
/// gente devolve pro Flutter — cada campo lá vem duplicado com dois nomes
/// possíveis (compatibilidade do lado deles), aqui só escolhe um.
function normalizarPedido(p: PedidoExternoBruto) {
  return {
    id: p.id ?? p.pedido ?? p.order_id ?? null,
    pedido: String(p.pedido ?? p.order_id ?? p.id ?? ""),
    cliente: p.cliente ?? p.customer ?? "",
    endereco: p.endereco ?? p.address ?? "",
    formaPagamento: p.forma_pagamento ?? p.pagamento ?? "",
    valorCobrar: p.valor_cobrar ?? p.valor ?? p.receber ?? 0,
    taxa: p.taxa ?? p.taxa_entrega ?? 0,
    status: p.status ?? p.status_entrega ?? "",
    loja: p.loja ?? "",
    localizador: p.localizador ?? "",
    dataHora: p.data_hora ?? "",
  };
}

// Esse router mistura rota do app (Flutter) e rotas de admin com bases
// diferentes — por isso usa caminhos completos e é montado na raiz em
// index.ts (`app.route("/", integracoesExternas)`), em vez do padrão de
// montar num prefixo e usar caminhos relativos.

// GET /api/integracoes/pedidos — chamado PELO FLUTTER (autenticado com o ID
// token do Firebase). Busca todas as integrações ativas desse motoboy e faz
// o GET em cada URL cadastrada — uma falha numa integração não derruba as
// outras nem a resposta inteira.
integracoesExternas.get("/api/integracoes/pedidos", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const { results } = await c.env.DB
    .prepare("SELECT id, nome, url, restaurante_uid FROM integracoes_externas WHERE motoboy_uid = ? AND ativo = 1")
    .bind(motoboy.uid)
    .all<{ id: number; nome: string; url: string; restaurante_uid: string | null }>();

  const { results: finalizadas } = await c.env.DB
    .prepare("SELECT integracao_id, pedido FROM entregas_externas_finalizadas WHERE motoboy_uid = ?")
    .bind(motoboy.uid)
    .all<{ integracao_id: number; pedido: string }>();
  const jaFinalizados = new Set(finalizadas.map((f) => `${f.integracao_id}:${f.pedido}`));

  const integracoes = await Promise.all(
    results.map(async (integracao) => {
      try {
        const resp = await fetch(integracao.url, { signal: AbortSignal.timeout(10_000) });
        const data = await resp.json<{ sucesso?: boolean; status?: string; pedidos?: PedidoExternoBruto[] }>().catch(() => null);

        if (!data || data.sucesso === false) {
          return { id: integracao.id, nome: integracao.nome, restauranteUid: integracao.restaurante_uid, status: data?.status === "bloqueado" ? "bloqueado" : "indisponivel", pedidos: [] };
        }

        const pedidos = (data.pedidos ?? [])
          .map(normalizarPedido)
          .filter((p) => !jaFinalizados.has(`${integracao.id}:${p.pedido}`));

        return { id: integracao.id, nome: integracao.nome, restauranteUid: integracao.restaurante_uid, status: "ok", pedidos };
      } catch (e) {
        console.log("DEBUG integração externa indisponível:", integracao.nome, e instanceof Error ? e.message : e);
        return { id: integracao.id, nome: integracao.nome, restauranteUid: integracao.restaurante_uid, status: "indisponivel", pedidos: [] };
      }
    }),
  );

  return c.json({ integracoes }, 200);
});

// POST /api/integracoes/:integracaoId/finalizar — chamado PELO FLUTTER
// quando o motoboy finaliza uma entrega de uma integração externa. O
// sistema externo é só leitura (não aceita evento de volta — "as baixas
// são feitas no painel interno" deles), então isso só grava por aqui que
// esse pedido já foi finalizado, pra ele parar de aparecer na lista (senão
// continuaria aparecendo pra sempre, já que o lado deles só some quando
// processado no painel interno deles).
integracoesExternas.post("/api/integracoes/:integracaoId/finalizar", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const integracaoId = Number(c.req.param("integracaoId"));
  if (!Number.isInteger(integracaoId)) return c.json({ error: "invalid_request" }, 400);

  const body = await c.req
    .json<{ pedido?: string; taxaCents?: number; valorTotalCents?: number; formaPagamento?: string }>()
    .catch(() => ({}) as { pedido?: string; taxaCents?: number; valorTotalCents?: number; formaPagamento?: string });
  const pedido = body.pedido?.trim();
  const taxaCents = typeof body.taxaCents === "number" ? body.taxaCents : 0;
  const valorTotalCents = typeof body.valorTotalCents === "number" ? body.valorTotalCents : 0;
  const formaPagamento = body.formaPagamento?.trim() || null;
  if (!pedido) return c.json({ error: "invalid_request", error_description: "pedido é obrigatório" }, 400);

  // Confere que essa integração é mesmo desse motoboy antes de gravar.
  const integracao = await c.env.DB
    .prepare("SELECT id FROM integracoes_externas WHERE id = ? AND motoboy_uid = ?")
    .bind(integracaoId, motoboy.uid)
    .first();
  if (!integracao) return c.json({ error: "not_found" }, 404);

  await c.env.DB
    .prepare(
      `INSERT INTO entregas_externas_finalizadas (motoboy_uid, integracao_id, pedido, taxa_cents, valor_total_cents, forma_pagamento)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(motoboy.uid, integracaoId, pedido, taxaCents, valorTotalCents, formaPagamento)
    .run();

  return c.json({ ok: true }, 200);
});

// ── Admin (cadastro/remoção — mesmo padrão de X-Admin-Key de adminLojas.ts) ─

// POST /admin/integracoes — cadastra uma integração nova pra um motoboy.
integracoesExternas.post("/admin/integracoes", async (c) => {
  if (!autorizadoAdmin(c)) return c.json({ error: "unauthorized" }, 401);

  const body = await c.req
    .json<{ motoboyUid?: string; nome?: string; url?: string; restauranteUid?: string }>()
    .catch(() => ({}) as { motoboyUid?: string; nome?: string; url?: string; restauranteUid?: string });

  const motoboyUid = body.motoboyUid?.trim();
  const nome = body.nome?.trim();
  const url = body.url?.trim();
  const restauranteUid = body.restauranteUid?.trim() || null;

  if (!motoboyUid || !nome || !url) {
    return c.json({ error: "invalid_request", error_description: "motoboyUid, nome e url são obrigatórios" }, 400);
  }

  const resultado = await c.env.DB
    .prepare("INSERT INTO integracoes_externas (motoboy_uid, nome, url, restaurante_uid) VALUES (?, ?, ?, ?)")
    .bind(motoboyUid, nome, url, restauranteUid)
    .run();

  return c.json({ id: resultado.meta.last_row_id, motoboyUid, nome, url, restauranteUid }, 201);
});

// GET /admin/integracoes — lista todas as integrações cadastradas.
integracoesExternas.get("/admin/integracoes", async (c) => {
  if (!autorizadoAdmin(c)) return c.json({ error: "unauthorized" }, 401);

  const { results } = await c.env.DB
    .prepare("SELECT id, motoboy_uid, nome, url, ativo, restaurante_uid, criado_em FROM integracoes_externas ORDER BY criado_em DESC")
    .all<{ id: number; motoboy_uid: string; nome: string; url: string; ativo: number; restaurante_uid: string | null; criado_em: string }>();

  return c.json(
    {
      registros: results.map((r) => ({
        id: r.id,
        motoboyUid: r.motoboy_uid,
        nome: r.nome,
        url: r.url,
        ativo: r.ativo === 1,
        restauranteUid: r.restaurante_uid,
        criadoEm: r.criado_em,
      })),
    },
    200,
  );
});

// DELETE /admin/integracoes/:id — remove uma integração.
integracoesExternas.delete("/admin/integracoes/:id", async (c) => {
  if (!autorizadoAdmin(c)) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  await c.env.DB.prepare("DELETE FROM integracoes_externas WHERE id = ?").bind(id).run();
  return c.json({ ok: true }, 200);
});
