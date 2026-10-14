// Geografia pra ajudar o restaurante a cadastrar bairros em lote (Fase
// 13.2): estados/cidades vêm do IBGE (fonte oficial, sempre completa);
// bairros vêm do OpenStreetMap via Overpass API (mesma fonte gratuita já
// usada no mapa de Localização) — bairro não é uma divisão administrativa
// oficial no Brasil, então essa lista é best-effort: cidades grandes
// tendem a vir completas, cidades pequenas podem vir vazias/incompletas
// (o Flutter já avisa isso e deixa adicionar manualmente).
import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";

export const geo = new Hono<{ Bindings: Env }>();

geo.get("/estados", async (c) => {
  const usuario = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!usuario) return c.json({ error: "unauthorized" }, 401);

  try {
    const resp = await fetch("https://servicodados.ibge.gov.br/api/v1/localidades/estados?orderBy=nome", {
      signal: AbortSignal.timeout(15_000),
    });
    const data = await resp.json<Array<{ sigla: string; nome: string }>>();
    return c.json({ estados: data.map((e) => ({ sigla: e.sigla, nome: e.nome })) }, 200);
  } catch (e) {
    return c.json({ error: "indisponivel" }, 502);
  }
});

geo.get("/municipios", async (c) => {
  const usuario = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!usuario) return c.json({ error: "unauthorized" }, 401);

  const uf = c.req.query("uf")?.trim().toUpperCase();
  if (!uf) return c.json({ error: "invalid_request", error_description: "uf é obrigatório" }, 400);

  try {
    const resp = await fetch(`https://servicodados.ibge.gov.br/api/v1/localidades/estados/${uf}/municipios`, {
      signal: AbortSignal.timeout(15_000),
    });
    const data = await resp.json<Array<{ nome: string }>>();
    return c.json({ municipios: data.map((m) => m.nome) }, 200);
  } catch (e) {
    return c.json({ error: "indisponivel" }, 502);
  }
});

async function buscarBairrosNoOverpass(cidade: string): Promise<string[] | null> {
  const cidadeEscapada = cidade.replace(/"/g, "");
  const query = `[out:json][timeout:20];area["name"="${cidadeEscapada}"]["boundary"="administrative"]["admin_level"="8"]->.a;(node["place"~"suburb|neighbourhood|quarter"](area.a);way["place"~"suburb|neighbourhood|quarter"](area.a);relation["place"~"suburb|neighbourhood|quarter"](area.a););out center tags;`;

  const resp = await fetch("https://overpass-api.de/api/interpreter", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      // Overpass/OSM exigem um User-Agent identificando o app — sem isso
      // a requisição é recusada (406).
      "User-Agent": "MotocaPremium/1.0 (+https://motocapremium.com)",
    },
    body: `data=${encodeURIComponent(query)}`,
    signal: AbortSignal.timeout(25_000),
  });
  if (!resp.ok) return null;

  const data = await resp.json<{ elements?: Array<{ tags?: { name?: string } }> }>();
  const nomes = new Set<string>();
  for (const el of data.elements ?? []) {
    const nome = el.tags?.name?.trim();
    if (nome) nomes.add(nome);
  }
  return [...nomes].sort((a, b) => a.localeCompare(b, "pt-BR"));
}

// GET /api/geo/bairros?cidade=Santos — busca no OpenStreetMap (Overpass
// API) os lugares marcados como bairro/subúrbio dentro da área
// administrativa dessa cidade. Sem chave, sem custo — mas também sem
// garantia de estar completo (depende de quanto a cidade foi mapeada por
// voluntários do OSM) nem de disponibilidade (é um servidor público
// compartilhado, sem SLA — já vimos na prática ele devolver 406/504/521
// em picos). Por isso cacheia o resultado no D1: depois da primeira busca
// bem-sucedida pra uma cidade, as próximas nem dependem do Overpass estar
// no ar.
geo.get("/bairros", async (c) => {
  const usuario = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!usuario) return c.json({ error: "unauthorized" }, 401);

  const cidade = c.req.query("cidade")?.trim();
  if (!cidade) return c.json({ error: "invalid_request", error_description: "cidade é obrigatório" }, 400);

  const emCache = await c.env.DB
    .prepare("SELECT bairros_json FROM bairros_cache WHERE cidade = ?")
    .bind(cidade)
    .first<{ bairros_json: string }>();
  if (emCache) {
    return c.json({ bairros: JSON.parse(emCache.bairros_json), erro: false }, 200);
  }

  // Servidor público instável — tenta 2 vezes antes de desistir.
  let bairros: string[] | null = null;
  for (let tentativa = 0; tentativa < 2 && bairros === null; tentativa++) {
    if (tentativa > 0) await new Promise((r) => setTimeout(r, 1500));
    try {
      bairros = await buscarBairrosNoOverpass(cidade);
    } catch {
      bairros = null;
    }
  }

  if (bairros === null) {
    // Overpass fora do ar mesmo depois de tentar de novo — o Flutter
    // mostra "tenta de novo" em vez de "essa cidade não tem bairro".
    return c.json({ bairros: [], erro: true }, 200);
  }

  await c.env.DB
    .prepare("INSERT INTO bairros_cache (cidade, bairros_json, atualizado_em) VALUES (?, ?, datetime('now'))")
    .bind(cidade, JSON.stringify(bairros))
    .run();

  return c.json({ bairros, erro: false }, 200);
});
