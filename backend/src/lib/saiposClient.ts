// Envia atualização de status de uma entrega pra Saipos.
// Endpoint confirmado na doc oficial da Saipos ("Rastreamento de eventos"):
// POST https://logistics-api.saipos.com/delivery-tracking/tracking-event-webhook
//
// Autenticação aqui é HMAC (não OAuth2) — confirmado na prática: testamos
// contra a loja real (merchant 3214be4a-c93e-4839-a318-bfc52827cb42) e a
// Saipos aceitou a assinatura (respondeu 400 de validação de payload, não
// 401/403 de autenticação).
//
// Campos vehicle/deliveryPrice/eta/deliveryPerson são obrigatórios pra
// qualquer evento que não seja PENDING/REJECTED/CANCELLED — confirmado tanto
// no schema oficial (DeliveryOrderEvent, ChosenVehicle, DeliveryPrice, ETA,
// DeliveryMan) quanto na prática (a Saipos rejeitou nosso primeiro teste real
// de ACCEPTED com 400 listando exatamente esses 4 campos como faltando).

import { assinarHmacSha256Hex } from "./hmac";
import type { EventoSaipos } from "./statusMap";
import type { Loja } from "./partnerAuth";

const SAIPOS_TRACKING_URL = "https://logistics-api.saipos.com/delivery-tracking/tracking-event-webhook";

interface EnviarEventoParams {
  loja: Loja;
  appId: string;
  deliveryId: string;
  orderId: string;
  orderDisplayId: string | null;
  customerName: string | null;
  event: EventoSaipos;
  message?: string;
  // Obrigatórios pra qualquer evento != PENDING/REJECTED/CANCELLED:
  deliveryFeeCents?: number;
  motoboyUid?: string;
  motoboyNome?: string;
  motoboyTelefone?: string;
  // Obrigatório especificamente pro evento REJECTED — confirmado na prática
  // (a Saipos rejeitou nosso primeiro teste real com 400 "rejectionInfo is
  // required for REJECTED events"). Enum fechado, valores do schema oficial
  // (DeliveryEventDenied).
  rejectionReason?:
    | "PRICE_EXCEEDED"
    | "VEHICLE_NOT_AVAILABLE"
    | "NO_DELIVERYPERSON_AVAILABLE"
    | "DOES_NOT_MEET_REQUESTED_TIMES"
    | "REGION_NOT_SERVED"
    | "INVALID_ADDRESS"
    | "OTHER";
}

const EVENTOS_SEM_CAMPOS_EXTRAS: EventoSaipos[] = ["PENDING", "REJECTED", "CANCELLED"];

export async function enviarEventoDeStatus(params: EnviarEventoParams): Promise<{ ok: boolean; status: number; body: string }> {
  const precisaCamposExtras = !EVENTOS_SEM_CAMPOS_EXTRAS.includes(params.event);

  const agora = new Date();
  const camposExtras = precisaCamposExtras
    ? {
        vehicle: {
          type: "MOTORBIKE_BAG",
          container: "NORMAL",
        },
        deliveryPrice: {
          price: { value: (params.deliveryFeeCents ?? 0) / 100, currency: "BRL" },
          pricingList: "NORMAL",
          additionalPricePercentual: 0,
        },
        eta: {
          updateMethod: "OFFLINE",
          pickupEtaInMinutes: 10,
          pickupEtaDatetime: new Date(agora.getTime() + 10 * 60 * 1000).toISOString(),
          deliveryEtaInMinutes: 30,
          deliveryEtaDatetime: new Date(agora.getTime() + 30 * 60 * 1000).toISOString(),
          maxDeliveryTime: new Date(agora.getTime() + 60 * 60 * 1000).toISOString(),
        },
        deliveryPerson: {
          id: params.motoboyUid ?? "desconhecido",
          name: params.motoboyNome ?? "Motoboy Motoca Premium",
          ...(params.motoboyTelefone ? { phone: params.motoboyTelefone } : {}),
        },
      }
    : {};

  const corpo = {
    deliveryId: params.deliveryId,
    orderId: params.orderId,
    orderDisplayId: params.orderDisplayId,
    merchant: { id: params.loja.merchant_id, name: params.loja.nome },
    event: {
      type: params.event,
      datetime: agora.toISOString(),
      ...(params.message ? { message: params.message } : {}),
      ...(params.event === "REJECTED"
        ? { rejectionInfo: { reason: params.rejectionReason ?? "OTHER" } }
        : {}),
    },
    customerName: params.customerName ?? "",
    ...camposExtras,
  };

  const corpoTexto = JSON.stringify(corpo);
  const assinatura = await assinarHmacSha256Hex(params.loja.client_secret, corpoTexto);

  const resp = await fetch(SAIPOS_TRACKING_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-App-Id": params.appId,
      "X-App-MerchantId": params.loja.merchant_id,
      "X-App-Signature": assinatura,
    },
    body: corpoTexto,
  });

  const texto = await resp.text();
  return { ok: resp.ok, status: resp.status, body: texto };
}

// Confirmação do código de 4 dígitos que o cliente passa pro motoboy.
// Contrato confirmado no schema oficial (DeliveryConfirmationCode via
// POST /v1/confirmationCode): {orderId, deliveryCode} -> 200 válido / 400
// inválido. A URL CONCRETA da Saipos pra esse endpoint específico não foi
// confirmada na doc deles (diferente do tracking-event-webhook, que eles
// confirmaram) — por isso vem de env.SAIPOS_CONFIRMATION_CODE_URL, vazia por
// padrão. Só chama de verdade quando essa var estiver configurada.
export async function confirmarCodigoNaSaipos(
  confirmationCodeUrl: string,
  loja: Loja,
  appId: string,
  orderId: string,
  deliveryCode: string,
): Promise<{ configurado: boolean; valido: boolean; status: number; body: string }> {
  if (!confirmationCodeUrl) {
    return { configurado: false, valido: false, status: 0, body: "" };
  }

  const corpo = { orderId, deliveryCode };
  const corpoTexto = JSON.stringify(corpo);
  const assinatura = await assinarHmacSha256Hex(loja.client_secret, corpoTexto);

  const resp = await fetch(confirmationCodeUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-App-Id": appId,
      "X-App-MerchantId": loja.merchant_id,
      "X-App-Signature": assinatura,
    },
    body: corpoTexto,
  });

  const texto = await resp.text();
  return { configurado: true, valido: resp.status === 200, status: resp.status, body: texto };
}
