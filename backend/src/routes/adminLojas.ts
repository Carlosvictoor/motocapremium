// Rotas administrativas — só o painel Admin do Flutter chama isso, nunca a
// Saipos nem os motoboys. Protegidas por uma chave fixa (X-App-Id não serve
// aqui; é X-Admin-Key), mesmo padrão de segurança que já existia no app
// (a senha do admin já vem embutida no Flutter — ver lib/admin.dart,
// kAdminSenha). Cada linha de `lojas` é um registro de UM entregador
// (motoboy) num restaurante — ver contexto completo em deliveriesScan.ts.
import { Hono } from "hono";
import type { Env } from "../index";

export const adminLojas = new Hono<{ Bindings: Env }>();

function autorizado(c: { req: { header(name: string): string | undefined }; env: Env }): boolean {
  const chave = c.req.header("x-admin-key");
  return !!chave && chave === c.env.ADMIN_API_KEY;
}

function gerarCredencial(bytes: number): string {
  const arr = new Uint8Array(bytes);
  crypto.getRandomValues(arr);
  return [...arr].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// POST /admin/lojas — cadastra um novo registro de entregador (motoboy +
// restaurante): recebe o Merchant ID que a Saipos gerou pra esse entregador
// (copiado da tela "Entregadores" > "Usar serviço de entrega"), gera
// Client ID/Client Secret novos e devolve tudo — o secret só é mostrado
// nessa resposta, não fica disponível de novo depois.
adminLojas.post("/", async (c) => {
  if (!autorizado(c)) return c.json({ error: "unauthorized" }, 401);

  const body = await c.req
    .json<{ merchantId?: string; motoboyUid?: string; nomeRestaurante?: string; restauranteUid?: string }>()
    .catch(() => ({}) as { merchantId?: string; motoboyUid?: string; nomeRestaurante?: string; restauranteUid?: string });

  const merchantId = body.merchantId?.trim();
  const motoboyUid = body.motoboyUid?.trim();
  const nomeRestaurante = body.nomeRestaurante?.trim();
  const restauranteUid = body.restauranteUid?.trim() || null;

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
      .bind(merchantId, nomeRestaurante, clientId, clientSecret, motoboyUid, restauranteUid)
      .run();
  } catch (e) {
    return c.json({ error: "conflict", error_description: "Esse Merchant ID já está cadastrado" }, 409);
  }

  return c.json({ merchantId, nomeRestaurante, motoboyUid, restauranteUid, clientId, clientSecret }, 201);
});

// GET /admin/lojas — lista todos os registros (sem o client_secret).
adminLojas.get("/", async (c) => {
  if (!autorizado(c)) return c.json({ error: "unauthorized" }, 401);

  const { results } = await c.env.DB
    .prepare(
      `SELECT id, merchant_id, nome, client_id, motoboy_uid, ambiente, restaurante_uid, criado_em
       FROM lojas ORDER BY nome ASC, criado_em ASC`,
    )
    .all<{ id: number; merchant_id: string; nome: string; client_id: string; motoboy_uid: string | null; ambiente: string; restaurante_uid: string | null; criado_em: string }>();

  return c.json(
    {
      registros: results.map((r) => ({
        id: r.id,
        merchantId: r.merchant_id,
        nomeRestaurante: r.nome,
        clientId: r.client_id,
        motoboyUid: r.motoboy_uid,
        ambiente: r.ambiente,
        restauranteUid: r.restaurante_uid,
        criadoEm: r.criado_em,
      })),
    },
    200,
  );
});

// DELETE /admin/lojas/:id — desativa o registro (o motoboy deixa de
// conseguir ver pedidos daquele restaurante e a credencial para de
// funcionar na Saipos, ver partnerAuth.ts). Não apaga de verdade: quebraria
// a FOREIGN KEY com pedidos antigos que usaram essa credencial (mesmo
// motivo de restauranteLojas.ts).
adminLojas.delete("/:id", async (c) => {
  if (!autorizado(c)) return c.json({ error: "unauthorized" }, 401);

  const id = Number(c.req.param("id"));
  if (!Number.isInteger(id)) return c.json({ error: "invalid_request" }, 400);

  await c.env.DB.prepare("UPDATE lojas SET ativo = 0 WHERE id = ?").bind(id).run();
  return c.json({ ok: true }, 200);
});
