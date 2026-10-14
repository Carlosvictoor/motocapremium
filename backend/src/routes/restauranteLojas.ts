// Mesma coisa que adminLojas.ts (gera Merchant ID/Client ID/Secret pra um
// registro de entregador na Saipos), só que self-service pro próprio
// restaurante logado — autenticado pelo ID token do Firebase (não pela
// X-Admin-Key), e sempre restrito ao restaurante_uid de quem chamou. Não dá
// pra escolher outro restaurante nem ver/apagar registro de outro (ver
// Fase 11.3 do plano) — só o motoboy_uid é livre, mas o Flutter já restringe
// isso aos motoboys que o restaurante vinculou (ver restaurante_dashboard.dart).
import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";

export const restauranteLojas = new Hono<{ Bindings: Env }>();

function gerarCredencial(bytes: number): string {
  const arr = new Uint8Array(bytes);
  crypto.getRandomValues(arr);
  return [...arr].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// POST /api/restaurante/lojas — o restaurante gera um registro novo pra um
// motoboy dele: recebe o Merchant ID que a Saipos gerou (copiado da tela
// "Entregadores" > "Usar serviço de entrega"), gera Client ID/Secret novos.
restauranteLojas.post("/", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const body = await c.req
    .json<{ merchantId?: string; motoboyUid?: string; nomeRestaurante?: string }>()
    .catch(() => ({}) as { merchantId?: string; motoboyUid?: string; nomeRestaurante?: string });

  const merchantId = body.merchantId?.trim();
  const motoboyUid = body.motoboyUid?.trim();
  const nomeRestaurante = body.nomeRestaurante?.trim();

  if (!merchantId || !motoboyUid || !nomeRestaurante) {
    return c.json({ error: "invalid_request", error_description: "merchantId, motoboyUid e nomeRestaurante são obrigatórios" }, 400);
  }

  const clientId = gerarCredencial(16);
  const clientSecret = gerarCredencial(32);

  try {
    await c.env.DB
      .prepare(
        `INSERT INTO lojas (merchant_id, nome, client_id, client_secret, motoboy_uid, ambiente, restaurante_uid)
         VALUES (?, ?, ?, ?, ?, 'sandbox', ?)`,
      )
      .bind(merchantId, nomeRestaurante, clientId, clientSecret, motoboyUid, restaurante.uid)
      .run();
  } catch (e) {
    return c.json({ error: "conflict", error_description: "Esse Merchant ID já está cadastrado" }, 409);
  }

  return c.json({ merchantId, nomeRestaurante, motoboyUid, restauranteUid: restaurante.uid, clientId, clientSecret }, 201);
});

// GET /api/restaurante/lojas — lista só os registros ATIVOS desse
// restaurante (sem o client_secret, mesmo padrão de adminLojas.ts). Um
// registro desativado (ver DELETE abaixo) some daqui, mesmo continuando no
// banco pra não quebrar o vínculo com pedidos antigos.
restauranteLojas.get("/", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const { results } = await c.env.DB
    .prepare(
      `SELECT id, merchant_id, nome, client_id, motoboy_uid, ambiente, criado_em
       FROM lojas WHERE restaurante_uid = ? AND ativo = 1 ORDER BY criado_em DESC`,
    )
    .bind(restaurante.uid)
    .all<{ id: number; merchant_id: string; nome: string; client_id: string; motoboy_uid: string | null; ambiente: string; criado_em: string }>();

  return c.json(
    {
      registros: results.map((r) => ({
        id: r.id,
        merchantId: r.merchant_id,
        nomeRestaurante: r.nome,
        clientId: r.client_id,
        motoboyUid: r.motoboy_uid,
        ambiente: r.ambiente,
        criadoEm: r.criado_em,
      })),
    },
    200,
  );
});

// GET /api/restaurante/lojas/:id/segredo — mostra de novo o Client
// ID/Secret de um registro já existente (o restaurante pode ter perdido a
// cópia inicial, que só aparece uma vez ao gerar). Só o dono desse
// restaurante consegue ver, mesmo padrão de autorização das outras rotas.
restauranteLojas.get("/:id/segredo", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  const registro = await c.env.DB
    .prepare("SELECT client_id, client_secret FROM lojas WHERE id = ? AND restaurante_uid = ?")
    .bind(id, restaurante.uid)
    .first<{ client_id: string; client_secret: string }>();
  if (!registro) return c.json({ error: "not_found" }, 404);

  return c.json({ clientId: registro.client_id, clientSecret: registro.client_secret }, 200);
});

// DELETE /api/restaurante/lojas/:id — desativa o registro (não apaga de
// verdade) se ele for mesmo desse restaurante. Apagar de verdade quebraria
// a FOREIGN KEY com pedidos antigos que usaram essa credencial (o D1 recusa
// o DELETE nesse caso) e corromperia o relatório histórico do restaurante —
// desativar tem o mesmo efeito prático pro restaurante (a credencial some
// da lista e para de funcionar na Saipos, ver partnerAuth.ts) sem esse risco.
restauranteLojas.delete("/:id", async (c) => {
  const restaurante = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!restaurante) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  const registro = await c.env.DB
    .prepare("SELECT id FROM lojas WHERE id = ? AND restaurante_uid = ?")
    .bind(id, restaurante.uid)
    .first();
  if (!registro) return c.json({ error: "not_found" }, 404);

  await c.env.DB.prepare("UPDATE lojas SET ativo = 0 WHERE id = ?").bind(id).run();
  return c.json({ ok: true }, 200);
});
