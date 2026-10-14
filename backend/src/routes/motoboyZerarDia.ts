// Sinal de sincronização (Fase 12): o app avisa aqui toda vez que o
// motoboy aperta "Zerar o dia" no Financeiro dele (ver main_shell.dart
// _zerarODia) — só grava o horário, não guarda nenhum dado financeiro em
// si (isso continua só no Firestore pessoal do motoboy). O relatório do
// restaurante (routes/restauranteRelatorio.ts) usa esse horário como o
// corte de "hoje" por motoboy.
import { Hono } from "hono";
import type { Env } from "../index";
import { validarFirebaseIdToken } from "../lib/firebaseAuth";

export const motoboyZerarDia = new Hono<{ Bindings: Env }>();

motoboyZerarDia.post("/", async (c) => {
  const motoboy = await validarFirebaseIdToken(c.req.header("authorization") ?? null, c.env.FIREBASE_PROJECT_ID);
  if (!motoboy) return c.json({ error: "unauthorized" }, 401);

  await c.env.DB
    .prepare(
      `INSERT INTO motoboy_zerado_em (motoboy_uid, zerado_em) VALUES (?, datetime('now'))
       ON CONFLICT (motoboy_uid) DO UPDATE SET zerado_em = excluded.zerado_em`,
    )
    .bind(motoboy.uid)
    .run();

  return c.json({ ok: true }, 200);
});
