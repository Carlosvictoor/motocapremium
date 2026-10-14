// Autenticação Saipos -> Motoca Premium: OAuth2 client_credentials.
// O Motoca Premium é quem gera clientId/clientSecret (um par por loja) e
// hospeda o /oauth/token — a Saipos troca esse par por um Bearer token
// opaco, que deve reenviar em toda chamada aos endpoints /v1/logistics/*.

export interface Loja {
  id: number;
  merchant_id: string;
  nome: string;
  client_id: string;
  client_secret: string;
  motoboy_uid: string | null;
  ambiente: string;
}

const TOKEN_TTL_SEGUNDOS = 3600;

function gerarTokenOpaco(): string {
  return crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
}

/** Confere client_id/client_secret e emite um novo Bearer token opaco. */
export async function emitirToken(
  db: D1Database,
  clientId: string,
  clientSecret: string,
): Promise<{ access_token: string; token_type: "Bearer"; expires_in: number } | null> {
  const loja = await db
    .prepare("SELECT id, client_secret FROM lojas WHERE client_id = ? AND ativo = 1")
    .bind(clientId)
    .first<{ id: number; client_secret: string }>();

  if (!loja || loja.client_secret !== clientSecret) return null;

  const token = gerarTokenOpaco();
  const expiraEm = new Date(Date.now() + TOKEN_TTL_SEGUNDOS * 1000).toISOString();

  await db
    .prepare("INSERT INTO oauth_tokens (token, loja_id, expira_em) VALUES (?, ?, ?)")
    .bind(token, loja.id, expiraEm)
    .run();

  return { access_token: token, token_type: "Bearer", expires_in: TOKEN_TTL_SEGUNDOS };
}

/** Valida um Bearer token opaco recebido da Saipos e devolve a loja associada. */
export async function validarToken(db: D1Database, bearer: string | null): Promise<Loja | null> {
  if (!bearer?.startsWith("Bearer ")) return null;
  const token = bearer.slice("Bearer ".length).trim();
  if (!token) return null;

  const row = await db
    .prepare(
      `SELECT l.id, l.merchant_id, l.nome, l.client_id, l.client_secret, l.motoboy_uid, l.ambiente
       FROM oauth_tokens t
       JOIN lojas l ON l.id = t.loja_id
       WHERE t.token = ? AND t.expira_em > datetime('now') AND l.ativo = 1`,
    )
    .bind(token)
    .first<Loja>();

  return row ?? null;
}
