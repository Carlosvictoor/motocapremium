// Fala com a API do Mercado Pago (checkout transparente) pra gerar e
// consultar cobranças Pix. Usa env.MP_ACCESS_TOKEN — token de teste durante
// o desenvolvimento, trocado pro de produção só depois de tudo validado
// (ver plano da Fase 6.3).

const MP_API = "https://api.mercadopago.com";

export interface PagamentoPixCriado {
  paymentId: string;
  qrCodeBase64: string;
  copiaCola: string;
  expiraEm: string;
}

export interface PagamentoMp {
  id: string;
  status: string; // "approved" | "pending" | "rejected" | "cancelled" | ...
  externalReference: string | null;
}

/// Cria uma cobrança Pix de [valorReais] pro [uid] do motoboy, identificado
/// pelo [email] (única info de pagador exigida pela Mercado Pago pra Pix).
export async function criarPagamentoPix(params: {
  accessToken: string;
  uid: string;
  email: string;
  valorReais: number;
  descricao: string;
}): Promise<PagamentoPixCriado> {
  const expiracao = new Date(Date.now() + 30 * 60 * 1000); // 30min pra pagar

  const resp = await fetch(`${MP_API}/v1/payments`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${params.accessToken}`,
      "Content-Type": "application/json",
      "X-Idempotency-Key": crypto.randomUUID(),
    },
    body: JSON.stringify({
      transaction_amount: params.valorReais,
      description: params.descricao,
      payment_method_id: "pix",
      external_reference: params.uid,
      date_of_expiration: expiracao.toISOString(),
      payer: { email: params.email },
    }),
  });

  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`Mercado Pago recusou criar o pagamento Pix (${resp.status}): ${body}`);
  }

  const json = await resp.json<{
    id: number;
    date_of_expiration: string;
    point_of_interaction?: { transaction_data?: { qr_code?: string; qr_code_base64?: string } };
  }>();

  const qrCodeBase64 = json.point_of_interaction?.transaction_data?.qr_code_base64;
  const copiaCola = json.point_of_interaction?.transaction_data?.qr_code;
  if (!qrCodeBase64 || !copiaCola) {
    throw new Error("Mercado Pago não devolveu o QR code do Pix na resposta.");
  }

  return {
    paymentId: String(json.id),
    qrCodeBase64,
    copiaCola,
    expiraEm: json.date_of_expiration,
  };
}

/// Busca o pagamento completo na Mercado Pago pelo id — usado pelo webhook,
/// que nunca deve confiar só no corpo da notificação recebida.
export async function buscarPagamento(accessToken: string, paymentId: string): Promise<PagamentoMp> {
  const resp = await fetch(`${MP_API}/v1/payments/${paymentId}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`Mercado Pago recusou consultar o pagamento ${paymentId} (${resp.status}): ${body}`);
  }
  const json = await resp.json<{ id: number; status: string; external_reference: string | null }>();
  return { id: String(json.id), status: json.status, externalReference: json.external_reference };
}
