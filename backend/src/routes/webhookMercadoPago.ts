import { Hono } from "hono";
import type { Env } from "../index";
import { buscarPagamento } from "../lib/mercadoPagoClient";

export const webhookMercadoPago = new Hono<{ Bindings: Env }>();

const TRINTA_DIAS_MS = 30 * 24 * 60 * 60 * 1000;

async function hmacSha256Hex(chave: string, mensagem: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(chave),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const assinatura = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(mensagem));
  return [...new Uint8Array(assinatura)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Confere se a notificação realmente veio da Mercado Pago, comparando o
// header x-signature (formato "ts=...,v1=...") contra um HMAC-SHA256 do
// manifest "id:{paymentId};request-id:{requestId};ts:{ts};", calculado com
// a chave secreta cadastrada no painel (env.MP_WEBHOOK_SECRET).
async function assinaturaValida(c: {
  req: { header: (n: string) => string | undefined };
  env: Env;
}, paymentId: string): Promise<boolean> {
  const xSignature = c.req.header("x-signature");
  const xRequestId = c.req.header("x-request-id");
  if (!xSignature || !xRequestId || !c.env.MP_WEBHOOK_SECRET) return false;

  const partes = Object.fromEntries(
    xSignature.split(",").map((p) => {
      const [k, v] = p.split("=");
      return [k?.trim(), v?.trim()];
    }),
  );
  const ts = partes["ts"];
  const v1 = partes["v1"];
  if (!ts || !v1) return false;

  const manifest = `id:${paymentId};request-id:${xRequestId};ts:${ts};`;
  const esperado = await hmacSha256Hex(c.env.MP_WEBHOOK_SECRET, manifest);
  return esperado === v1;
}

// POST /webhooks/mercadopago — chamado PELA MERCADO PAGO quando o status de
// um pagamento muda. Nunca confia no corpo da notificação: sempre busca o
// pagamento completo de novo na API antes de liberar qualquer coisa.
webhookMercadoPago.post("/", async (c) => {
  const url = new URL(c.req.url);
  const paymentId = url.searchParams.get("data.id") ?? url.searchParams.get("id");
  const tipo = url.searchParams.get("type") ?? url.searchParams.get("topic");

  if (!paymentId || (tipo && tipo !== "payment")) {
    return c.json({ ok: true }, 200); // notificação de outro tipo, ignora
  }

  const valida = await assinaturaValida(c, paymentId);
  if (!valida) {
    console.log("DEBUG webhook Mercado Pago com assinatura inválida, paymentId:", paymentId);
    return c.json({ error: "invalid_signature" }, 401);
  }

  let pagamento;
  try {
    pagamento = await buscarPagamento(c.env.MP_ACCESS_TOKEN, paymentId);
  } catch (e) {
    console.log("DEBUG erro ao buscar pagamento do webhook:", e instanceof Error ? e.message : e);
    return c.json({ error: "mp_error" }, 502);
  }

  if (pagamento.status !== "approved" || !pagamento.externalReference) {
    return c.json({ ok: true }, 200);
  }

  const uid = pagamento.externalReference;

  // Idempotência: se esse payment_id já foi processado antes (reenvio da
  // Mercado Pago), não estende os 30 dias de novo.
  const jaProcessado = await c.env.DB
    .prepare("SELECT 1 FROM pagamentos_pix_processados WHERE payment_id = ?")
    .bind(pagamento.id)
    .first();
  if (jaProcessado) return c.json({ ok: true }, 200);

  const atual = await c.env.DB
    .prepare("SELECT expira_em FROM assinaturas_pix WHERE motoboy_uid = ?")
    .bind(uid)
    .first<{ expira_em: string }>();

  const base = atual && new Date(atual.expira_em).getTime() > Date.now()
    ? new Date(atual.expira_em).getTime()
    : Date.now();
  const novaExpiracao = new Date(base + TRINTA_DIAS_MS).toISOString();

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO assinaturas_pix (motoboy_uid, expira_em, atualizado_em) VALUES (?, ?, datetime('now'))
       ON CONFLICT(motoboy_uid) DO UPDATE SET expira_em = excluded.expira_em, atualizado_em = datetime('now')`,
    ).bind(uid, novaExpiracao),
    c.env.DB.prepare("INSERT INTO pagamentos_pix_processados (payment_id, motoboy_uid) VALUES (?, ?)").bind(pagamento.id, uid),
  ]);

  return c.json({ ok: true }, 200);
});
