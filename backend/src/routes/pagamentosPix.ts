import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";
import { criarPagamentoPix } from "../lib/mercadoPagoClient";

export const pagamentosPix = new Hono<{ Bindings: Env }>();

const VALOR_ASSINATURA_REAIS = 2.0;

// POST /api/pagamentos/pix — chamado PELO FLUTTER (Web, onde não existe Play
// Store) quando o motoboy toca em "Pagar com Pix" na tela de assinatura.
// Gera uma cobrança na Mercado Pago com external_reference = uid, pra o
// webhook (webhookMercadoPago.ts) saber de quem é o pagamento quando ele
// for aprovado.
pagamentosPix.post("/", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);
  if (!motoboy.email) {
    return c.json({ error: "invalid_request", error_description: "Conta sem email associado." }, 400);
  }

  try {
    const pagamento = await criarPagamentoPix({
      accessToken: c.env.MP_ACCESS_TOKEN,
      uid: motoboy.uid,
      email: motoboy.email,
      valorReais: VALOR_ASSINATURA_REAIS,
      descricao: "Assinatura Motoca Premium (30 dias)",
    });
    return c.json({
      paymentId: pagamento.paymentId,
      qrCodeBase64: pagamento.qrCodeBase64,
      copiaCola: pagamento.copiaCola,
      expiraEm: pagamento.expiraEm,
    });
  } catch (e) {
    console.log("DEBUG erro ao criar pagamento Pix:", e instanceof Error ? e.message : e);
    return c.json({ error: "mp_error", error_description: "Não foi possível gerar o Pix agora. Tente de novo." }, 502);
  }
});

// GET /api/pagamentos/status — o Flutter fica chamando isso enquanto o
// diálogo do QR code estiver aberto, pra saber quando o webhook confirmou o
// pagamento e liberar a tela sozinho.
pagamentosPix.get("/status", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  const row = await c.env.DB
    .prepare("SELECT expira_em FROM assinaturas_pix WHERE motoboy_uid = ?")
    .bind(motoboy.uid)
    .first<{ expira_em: string }>();

  if (!row) return c.json({ ativo: false, expiraEm: null });

  const ativo = new Date(row.expira_em).getTime() > Date.now();
  return c.json({ ativo, expiraEm: row.expira_em });
});
