import { Hono } from "hono";
import { cors } from "hono/cors";
import { oauthToken } from "./routes/oauthToken";
import { logisticsDelivery } from "./routes/logisticsDelivery";
import { logisticsCancel } from "./routes/logisticsCancel";
import { deliveriesScan } from "./routes/deliveriesScan";
import { deliveriesAccept } from "./routes/deliveriesAccept";
import { deliveriesList } from "./routes/deliveriesList";
import { deliveriesConfirmarCodigo } from "./routes/deliveriesConfirmarCodigo";
import { deliveriesFinalizar } from "./routes/deliveriesFinalizar";
import { deliveriesRejeitar } from "./routes/deliveriesRejeitar";
import { adminLojas } from "./routes/adminLojas";
import { restauranteLojas } from "./routes/restauranteLojas";
import { restauranteRelatorio } from "./routes/restauranteRelatorio";
import { restauranteFinanceiro } from "./routes/restauranteFinanceiro";
import { motoboyZerarDia } from "./routes/motoboyZerarDia";
import { geo } from "./routes/geo";
import { pagamentosPix } from "./routes/pagamentosPix";
import { webhookMercadoPago } from "./routes/webhookMercadoPago";
import { integracoesExternas } from "./routes/integracoesExternas";

export interface Env {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  SAIPOS_APP_ID: string;
  SAIPOS_CONFIRMATION_CODE_URL: string;
  ADMIN_API_KEY: string;
  MP_ACCESS_TOKEN: string;
  MP_WEBHOOK_SECRET: string;
}

const app = new Hono<{ Bindings: Env }>();

// A versão Web do app (motoca-premium-app.motoca-premium.workers.dev, e o
// domínio próprio motocapremium.com) chama esse backend direto do
// navegador — sem CORS liberado pra essas origens, toda chamada de lá é
// bloqueada antes mesmo de chegar aqui. Restrito só nas rotas /api/* (em
// vez de "*") como defesa em profundidade: mesmo autenticado só por Bearer
// token (sem cookie, então sem brecha de CSRF), liberar geral permitiria
// qualquer site do navegador usar um token vazado por outro meio pra chamar
// a API como se fosse o app.
//
// IMPORTANTE: isso NÃO pode se aplicar a /oauth/token nem /v1/logistics/* —
// são chamadas pela Saipos, e pelo menos a validação de credencial na tela
// deles ("Entregadores > Usar serviço de entrega") faz a checagem direto do
// navegador DELES, não do servidor. Restringir CORS ali quebra o preflight
// (o navegador da Saipos barra a requisição antes de sair, sem nem chegar
// aqui) mesmo sem afetar em nada a chamada normal de pedido, que é
// servidor-a-servidor — foi exatamente isso que quebrou a conexão de um
// restaurante em 2026-09-10. Essas rotas nunca tiveram (nem precisam de)
// proteção por CORS: a autenticação delas é client_id/secret + HMAC, não
// cookie de sessão, então CORS aberto ali não é uma brecha de segurança.
const ORIGENS_PERMITIDAS = [
  "https://motocapremium.com",
  "https://www.motocapremium.com",
  "https://motoca-premium-app.motoca-premium.workers.dev",
];
app.use(
  "/api/*",
  cors({
    origin: (origin) => {
      if (!origin) return undefined;
      if (ORIGENS_PERMITIDAS.includes(origin)) return origin;
      if (/^http:\/\/localhost(:\d+)?$/.test(origin)) return origin; // dev local (flutter run -d chrome)
      return undefined;
    },
  }),
);

// CORS aberto (não ausente!) nas rotas da Saipos — sem isso, um preflight
// OPTIONS nelas cai 404 (nenhuma rota trata OPTIONS) e qualquer chamada
// vinda do navegador da Saipos é bloqueada antes de sair, igual ao bug de
// CORS restrito acima. `cors()` sem opções libera geral, o mesmo
// comportamento de antes de restringir CORS pela primeira vez.
app.use("/oauth/token", cors());
app.use("/v1/logistics/*", cors());

app.get("/", (c) => c.json({ ok: true, service: "motoca-premium-backend" }));

// Chamado pela Saipos:
app.route("/oauth/token", oauthToken);
app.route("/v1/logistics/delivery", logisticsDelivery);
app.route("/v1/logistics/cancel", logisticsCancel);

// Chamado pelo app Flutter (autenticado com o ID token do Firebase):
app.route("/api/deliveries/scan", deliveriesScan);
app.route("/api/deliveries", deliveriesAccept);
app.route("/api/deliveries", deliveriesList);
app.route("/api/deliveries", deliveriesConfirmarCodigo);
app.route("/api/deliveries", deliveriesFinalizar);
app.route("/api/deliveries", deliveriesRejeitar);

// Chamado só pelo painel Admin do Flutter (chave fixa, ver routes/adminLojas.ts):
app.route("/admin/lojas", adminLojas);

// Chamado pelo painel do restaurante (autenticado com o ID token do
// Firebase do próprio restaurante logado, ver routes/restauranteLojas.ts):
app.route("/api/restaurante/lojas", restauranteLojas);
app.route("/api/restaurante/relatorio", restauranteRelatorio);
app.route("/api/restaurante/financeiro", restauranteFinanceiro);

// Chamado pelo app do motoboy toda vez que ele aperta "Zerar o dia" (só um
// sinal de sincronização pro relatório do restaurante, ver motoboyZerarDia.ts):
app.route("/api/motoboy/zerar-dia", motoboyZerarDia);

// Geografia (IBGE + OpenStreetMap) pra ajudar a cadastrar bairros em lote
// no painel do restaurante (ver routes/geo.ts):
app.route("/api/geo", geo);

// Assinatura mensal via Pix (só a versão Web, sem Play Store):
app.route("/api/pagamentos", pagamentosPix);
// Chamado pela Mercado Pago:
app.route("/webhooks/mercadopago", webhookMercadoPago);

// Integrações externas de leitura (outros sistemas de delivery, além da
// Saipos) — router usa caminhos completos (/api/integracoes/... e
// /admin/integracoes/...), por isso é montado na raiz.
app.route("/", integracoesExternas);

export default app;
