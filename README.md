# Motoca Premium

Aplicativo para motoboys controlarem entregas, ganhos e gastos, integrado a restaurantes e sistemas de delivery.
Roda no Android e na web ([motocapremium.com](https://motocapremium.com)).

## Funcionalidades

**Para o motoboy**
- Registro de cada saída do dia (comanda, taxa, gorjeta e plataforma), com totais de saídas, ganho, KM e tempo online
- Pedidos recebidos dos restaurantes integrados, com confirmação de entrega por leitura de QR code ou código
- Aba Financeiro: lançamento de gastos, resumo do dia e da semana e histórico por mês
- Fechamento do mês com ganho, gastos, lucro, gráfico semanal e melhor dia
- Envio do resumo do dia pelo WhatsApp
- Feed da comunidade com posts, curtidas e comentários

**Para o restaurante**
- Taxa de entrega configurada por bairro
- Vínculo com os motoboys que já usam o app
- Relatórios e controle financeiro dos motoboys, com exportação em PDF

**Administração e acesso**
- Teste grátis, assinatura pela Play Store, pagamento via PIX (Mercado Pago) ou código de acesso
- Painel admin para liberar ou revogar acesso e gerar códigos

## Integrações

- **Saipos:** recebe pedidos no padrão Open Delivery, com autenticação OAuth (client_id/secret) e assinatura HMAC
- **Mercado Pago:** cobrança via PIX com confirmação automática por webhook
- **Firebase:** login dos usuários; o backend valida o token do Firebase em cada requisição

## Tecnologias

| Parte | Tecnologias |
|---|---|
| App | Flutter (Dart), Firebase Auth e Firestore, SQLite local, fl_chart, flutter_map, mobile_scanner, pdf |
| Backend | TypeScript, Hono, Cloudflare Workers |
| Banco de dados | Cloudflare D1 (SQLite) |
| Hospedagem web | Cloudflare (domínio próprio) |

O backend também tem CORS restrito às origens do app e limite de tentativas contra força bruta nas rotas sensíveis.

## Estrutura

```
lib/                 App Flutter
  pedidos/           Pedidos e confirmação de entrega
  restaurante/       Telas e serviços do restaurante
  feed/              Feed da comunidade
backend/
  src/routes/        Rotas da API (entregas, restaurantes, PIX, webhooks, integrações)
  src/lib/           Autenticação Firebase, HMAC, clientes Saipos e Mercado Pago, rate limit
  db/schema.sql      Tabelas do banco D1
```

## Como rodar

**App**

```bash
flutter pub get
flutter run            # Android ou emulador
flutter run -d chrome  # versão web
```

**Backend**

```bash
cd backend
npm install
npm run db:apply:local   # cria as tabelas no D1 local
npm run dev
```

Os segredos (`MP_ACCESS_TOKEN`, `MP_WEBHOOK_SECRET`, `ADMIN_API_KEY`) são configurados com `wrangler secret put` e não ficam no código.
