import { Hono } from "hono";
import type { Env } from "../index";
import { emitirToken } from "../lib/partnerAuth";
import { limiteExcedido } from "../lib/rateLimit";

export const oauthToken = new Hono<{ Bindings: Env }>();

// POST /oauth/token — a Saipos troca clientId/clientSecret por um Bearer.
// Aceita application/x-www-form-urlencoded (padrão OAuth2 client_credentials)
// e também JSON, para facilitar teste manual com curl.
oauthToken.post("/", async (c) => {
  let clientId: string | undefined;
  let clientSecret: string | undefined;
  let grantType: string | undefined;

  const contentType = c.req.header("content-type") ?? "";
  if (contentType.includes("application/x-www-form-urlencoded")) {
    const form = await c.req.parseBody();
    clientId = typeof form.client_id === "string" ? form.client_id : undefined;
    clientSecret = typeof form.client_secret === "string" ? form.client_secret : undefined;
    grantType = typeof form.grant_type === "string" ? form.grant_type : undefined;
  } else {
    const body = await c.req.json().catch(() => ({}));
    clientId = body.client_id;
    clientSecret = body.client_secret;
    grantType = body.grant_type;
  }

  if (grantType && grantType !== "client_credentials") {
    return c.json({ error: "unsupported_grant_type" }, 400);
  }
  if (!clientId || !clientSecret) {
    return c.json({ error: "invalid_request", error_description: "client_id e client_secret são obrigatórios" }, 400);
  }

  // Sem isso nada impede martelar esse endpoint tentando adivinhar um
  // client_secret (32 bytes aleatórios — inviável na prática, mas o limite
  // evita abuso/DoS barato). Duas chaves: uma por client_id (força bruta
  // num alvo específico) e uma por IP (varrer vários client_id).
  const ip = c.req.header("cf-connecting-ip") ?? "desconhecido";
  const [porClientId, porIp] = await Promise.all([
    limiteExcedido(c.env.DB, `oauth:${clientId}`, 10, 300),
    limiteExcedido(c.env.DB, `oauth-ip:${ip}`, 30, 300),
  ]);
  if (porClientId || porIp) {
    return c.json({ error: "too_many_requests", error_description: "Muitas tentativas. Aguarde e tente de novo." }, 429);
  }

  const token = await emitirToken(c.env.DB, clientId, clientSecret);
  if (!token) {
    return c.json({ error: "invalid_client" }, 401);
  }

  return c.json(token, 200);
});
