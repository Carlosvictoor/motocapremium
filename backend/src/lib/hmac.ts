// Assinatura HMAC-SHA256 usada no header X-App-Signature ao chamar a Saipos
// (webhook de status) — hex minúsculo do corpo da requisição, chave = clientSecret
// daquela loja. Confirmado na doc oficial (Open Delivery), ver plano.

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function assinarHmacSha256Hex(secret: string, body: string): Promise<string> {
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
