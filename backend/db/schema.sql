-- Esquema inicial do backend Motoca Premium (integração Saipos Logística).
-- Fica isolado do Firestore/SQLite local do app — só guarda pedidos/entregas.

-- Cada linha representa um registro de ENTREGADOR (motoboy) num restaurante
-- específico — confirmado na tela real da Saipos ("Entregadores" > "Usar
-- serviço de entrega"): o Merchant ID é gerado por lá por entregador
-- individual, não por restaurante inteiro. motoboy_uid é quem esse registro
-- pertence; só esse motoboy consegue ver/escanear pedidos dessa loja.
CREATE TABLE IF NOT EXISTS lojas (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  merchant_id    TEXT NOT NULL UNIQUE, -- merchantId gerado pela Saipos pra esse entregador
  nome           TEXT NOT NULL,        -- nome do restaurante
  client_id      TEXT NOT NULL UNIQUE, -- gerado por nós, entregue à Saipos
  client_secret  TEXT NOT NULL,        -- gerado por nós; usado no OAuth2 e no HMAC
  motoboy_uid    TEXT,                 -- Firebase uid do motoboy dono desse registro
  ambiente       TEXT NOT NULL DEFAULT 'sandbox', -- 'sandbox' | 'producao'
  restaurante_uid TEXT,                -- Firebase uid da conta de restaurante dona dessa loja (Fase 11.1), opcional
  ativo          INTEGER NOT NULL DEFAULT 1, -- 0 = desativada (não pode mais ser usada nem aparecer na lista), mas não é apagada de verdade pra não quebrar o vínculo com pedidos antigos usados nos relatórios
  criado_em      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS oauth_tokens (
  token       TEXT PRIMARY KEY,   -- token opaco (Bearer) devolvido no /oauth/token
  loja_id     INTEGER NOT NULL REFERENCES lojas(id),
  expira_em   TEXT NOT NULL,      -- ISO datetime
  criado_em   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS pedidos (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  loja_id             INTEGER NOT NULL REFERENCES lojas(id),
  order_id            TEXT NOT NULL,   -- UUID gerado pela Saipos
  order_display_id    TEXT,            -- número exibido pro cliente (candidato ao código de barras)
  delivery_id         TEXT NOT NULL UNIQUE, -- UUID gerado por nós, devolvido no 202
  status              TEXT NOT NULL DEFAULT 'DISPONIVEL',
  -- DISPONIVEL | ACEITA | RETIRADA | EM_ENTREGA | ENTREGUE | REJEITADA | CANCELADA
  customer_name       TEXT,
  delivery_address    TEXT,           -- JSON serializado (endereço completo do Open Delivery)
  payment_method      TEXT,           -- OFFLINE | ONLINE
  payment_type        TEXT,           -- CREDIT | DEBIT | PIX | CASH | ...
  order_total_cents   INTEGER,        -- valor do pedido em centavos
  delivery_fee_cents  INTEGER,        -- taxa do motoboy em centavos (original da Saipos — sempre isso que é mandado de volta pra Saipos)
  delivery_fee_final_cents INTEGER,   -- taxa efetiva (Fase 12), só quando sobreposta por bairro (Fase 11.1); NULL = usa delivery_fee_cents mesmo
  observacoes         TEXT,
  motoboy_uid         TEXT,           -- Firebase uid do motoboy dono/atribuído (já vem da loja na criação, ver logisticsDelivery.ts; só fica null em pedidos antigos ou se a loja não tiver motoboy_uid)
  confirmation_code_required INTEGER NOT NULL DEFAULT 0, -- Saipos pede código de 4 dígitos do cliente pra finalizar
  codigo_confirmado   INTEGER NOT NULL DEFAULT 0,         -- só permite finalizar depois de confirmado (quando exigido)
  payload_raw         TEXT NOT NULL,  -- JSON bruto recebido da Saipos (auditoria/debug)
  criado_em           TEXT NOT NULL DEFAULT (datetime('now')),
  atualizado_em       TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (loja_id, order_id)
);

CREATE INDEX IF NOT EXISTS idx_pedidos_display_id ON pedidos (order_display_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_status ON pedidos (status);
CREATE INDEX IF NOT EXISTS idx_pedidos_motoboy ON pedidos (motoboy_uid);

CREATE TABLE IF NOT EXISTS motoboys_lojas (
  motoboy_uid   TEXT NOT NULL,  -- uid do Firebase Auth (mesmo uid do app Flutter)
  loja_id       INTEGER NOT NULL REFERENCES lojas(id),
  criado_em     TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (motoboy_uid, loja_id)
);

-- Assinatura mensal paga via Pix (Mercado Pago) — só usado pela versão web,
-- onde não existe Play Store. Vencimento estendido em 30 dias a cada
-- pagamento aprovado (ver webhookMercadoPago.ts), igual ao código de acesso.
CREATE TABLE IF NOT EXISTS assinaturas_pix (
  motoboy_uid   TEXT PRIMARY KEY,
  expira_em     TEXT NOT NULL,
  atualizado_em TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Trava de idempotência: o Mercado Pago pode reenviar o mesmo webhook mais
-- de uma vez, isso evita estender os 30 dias duas vezes pro mesmo pagamento.
CREATE TABLE IF NOT EXISTS pagamentos_pix_processados (
  payment_id     TEXT PRIMARY KEY,
  motoboy_uid    TEXT NOT NULL,
  processado_em  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Integrações externas de leitura (outros sistemas de delivery, além da
-- Saipos) — cada linha é um sistema que esse motoboy quer ver os pedidos
-- dentro do Motoca Premium. Só leitura: a gente busca essa URL e mostra,
-- não manda evento nenhum de volta (ver routes/integracoesExternas.ts).
CREATE TABLE IF NOT EXISTS integracoes_externas (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  motoboy_uid     TEXT NOT NULL,
  nome            TEXT NOT NULL,
  url             TEXT NOT NULL,
  ativo           INTEGER NOT NULL DEFAULT 1,
  restaurante_uid TEXT,   -- Firebase uid da conta de restaurante dona (Fase 11.1), opcional
  criado_em       TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Marca quais pedidos de integrações externas o motoboy já finalizou por
-- aqui — como o sistema externo é só leitura, ele não sabe que finalizamos,
-- então sem isso o mesmo pedido apareceria pra sempre na lista.
CREATE TABLE IF NOT EXISTS entregas_externas_finalizadas (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  motoboy_uid        TEXT NOT NULL,
  integracao_id      INTEGER NOT NULL,
  pedido             TEXT NOT NULL,
  taxa_cents         INTEGER NOT NULL DEFAULT 0, -- taxa efetiva no momento de finalizar (Fase 12, pro relatório do restaurante)
  valor_total_cents  INTEGER NOT NULL DEFAULT 0, -- valor do pedido em si (não a taxa) — pro total de vendas (Fase 12.2)
  forma_pagamento    TEXT,                       -- texto livre vindo do sistema externo (ex.: "ONLINE (PAGO)") — bucket cartão/dinheiro/pix é heurística de texto, não campo estruturado
  criado_em          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Timestamp do último "Zerar o dia" de cada motoboy (ver
-- lib/main_shell.dart _zerarODia) — usado pelo relatório do restaurante
-- (Fase 12) como o corte de "hoje": entregas finalizadas depois desse
-- horário contam como do período aberto atual, as de antes só entram no
-- total histórico. Sem relação com o Financeiro pessoal do motoboy em si
-- (esse continua só no Firestore) — é só um sinal de sincronização.
CREATE TABLE IF NOT EXISTS motoboy_zerado_em (
  motoboy_uid TEXT PRIMARY KEY,
  zerado_em   TEXT NOT NULL
);

-- Igual acima, mas o corte é disparado pelo PRÓPRIO RESTAURANTE (botão
-- "Zerar o dia" manual na aba Relatório, Fase 12.1) em vez do motoboy —
-- por par (restaurante, motoboy), pra não afetar o relatório de outro
-- restaurante que esse mesmo motoboy também atenda. O corte final usado
-- no relatório é o mais recente entre este e motoboy_zerado_em.
CREATE TABLE IF NOT EXISTS restaurante_motoboy_zerado_em (
  restaurante_uid TEXT NOT NULL,
  motoboy_uid     TEXT NOT NULL,
  zerado_em       TEXT NOT NULL,
  PRIMARY KEY (restaurante_uid, motoboy_uid)
);

-- Cache dos bairros encontrados no OpenStreetMap (Overpass API) pra cada
-- cidade (Fase 13.2, routes/geo.ts) — o servidor público do Overpass não
-- tem SLA e já foi visto retornando erro (406/504/521) em picos; depois
-- da primeira busca bem-sucedida de uma cidade, as próximas usam esse
-- cache em vez de depender do Overpass estar de pé.
CREATE TABLE IF NOT EXISTS bairros_cache (
  cidade        TEXT PRIMARY KEY,
  bairros_json  TEXT NOT NULL,
  atualizado_em TEXT NOT NULL
);

-- Rate limit genérico (ver backend/src/lib/rateLimit.ts) — uma linha por
-- tentativa; a "chave" identifica o que está sendo limitado (ex.:
-- "oauth:<clientId>", "oauth-ip:<ip>"). Linhas fora da janela de tempo são
-- limpas oportunisticamente a cada checagem da mesma chave.
CREATE TABLE IF NOT EXISTS rate_limit_hits (
  chave     TEXT NOT NULL,
  criado_em TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_rate_limit_chave ON rate_limit_hits (chave, criado_em);

-- "Fechar mês" da aba Financeiro do restaurante (Fase 13.3): cada linha é
-- um período fechado, com o total já calculado e congelado ali (não
-- recalcula depois, mesmo que o dado bruto de pedidos/entregas continue
-- existindo pra sempre no D1). O período "atual" mostrado na aba
-- Financeiro é sempre a partir do periodo_fim do fechamento mais recente
-- (ou desde sempre, se nunca fechou) — fechar um mês novo é o que "zera"
-- os números da tela pra esse restaurante.
CREATE TABLE IF NOT EXISTS restaurante_fechamentos (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  restaurante_uid      TEXT NOT NULL,
  periodo_inicio       TEXT NOT NULL,
  periodo_fim          TEXT NOT NULL,
  saidas               INTEGER NOT NULL DEFAULT 0,
  total_vendas_cents   INTEGER NOT NULL DEFAULT 0,
  total_taxas_cents    INTEGER NOT NULL DEFAULT 0,
  total_credito_cents  INTEGER NOT NULL DEFAULT 0,
  total_debito_cents   INTEGER NOT NULL DEFAULT 0,
  total_cartao_cents   INTEGER NOT NULL DEFAULT 0,
  total_dinheiro_cents INTEGER NOT NULL DEFAULT 0,
  total_pix_cents      INTEGER NOT NULL DEFAULT 0,
  total_outros_cents   INTEGER NOT NULL DEFAULT 0,
  criado_em            TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_fechamentos_restaurante ON restaurante_fechamentos (restaurante_uid, periodo_fim);

-- "Zerar tudo" da aba Financeiro (Fase 13.3.1) — reset rápido, sem
-- guardar nenhum snapshot em restaurante_fechamentos (ao contrário do
-- "Fechar mês"): só marca um corte de tempo, mesmo padrão de
-- motoboy_zerado_em/restaurante_motoboy_zerado_em. Ao usar, apaga também
-- todo o histórico de restaurante_fechamentos desse restaurante — é
-- destrutivo de verdade, ao contrário do "Fechar mês".
CREATE TABLE IF NOT EXISTS restaurante_financeiro_zerado_em (
  restaurante_uid TEXT PRIMARY KEY,
  zerado_em       TEXT NOT NULL
);
