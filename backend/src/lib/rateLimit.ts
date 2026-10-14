// Rate limit simples baseado no D1 (o worker não tem KV nem Durable
// Objects, ver backend/wrangler.toml) — reaproveitável por qualquer endpoint
// sensível a força bruta/abuso, não só o /oauth/token.

export async function limiteExcedido(
  db: D1Database,
  chave: string,
  maxTentativas: number,
  janelaSegundos: number,
): Promise<boolean> {
  const desde = new Date(Date.now() - janelaSegundos * 1000).toISOString();

  const contagem = await db
    .prepare("SELECT COUNT(*) AS total FROM rate_limit_hits WHERE chave = ? AND criado_em > ?")
    .bind(chave, desde)
    .first<{ total: number }>();

  if ((contagem?.total ?? 0) >= maxTentativas) return true;

  await db.prepare("INSERT INTO rate_limit_hits (chave) VALUES (?)").bind(chave).run();

  // Limpeza oportunista: some com as tentativas antigas dessa mesma chave
  // pra tabela não crescer pra sempre (não precisa de um cron separado).
  await db.prepare("DELETE FROM rate_limit_hits WHERE chave = ? AND criado_em <= ?").bind(chave, desde).run();

  return false;
}
