// Mapeamento status interno (Motoca Premium) <-> evento Saipos (Open Delivery).
// Enum Saipos é fechado — não inventar valores fora do que a doc oficial define.

export type StatusInterno =
  | "DISPONIVEL"
  | "ACEITA"
  | "RETIRADA"
  | "EM_ENTREGA"
  | "ENTREGUE"
  | "REJEITADA"
  | "CANCELADA";

export type EventoSaipos =
  | "PENDING"
  | "ACCEPTED"
  | "REJECTED"
  | "PICKUP_ONGOING"
  | "ARRIVED_AT_MERCHANT"
  | "READY_FOR_PICKUP"
  | "READY_FOR_PICKUP_NOTIFIED"
  | "READY_FOR_PICKUP_ATTEMPTED"
  | "ORDER_PICKED"
  | "DELIVERY_ONGOING"
  | "ARRIVED_AT_CUSTOMER"
  | "ORDER_DELIVERED"
  | "RETURNING_TO_MERCHANT"
  | "RETURNED_TO_MERCHANT"
  | "DELIVERY_FINISHED"
  | "CANCELLED";

// DISPONIVEL nunca é enviado como evento pra Saipos: PENDING só vai no corpo
// do 202 de resposta ao POST /logistics/delivery (ver routes/logisticsDelivery.ts).
export const STATUS_PARA_EVENTO_SAIPOS: Partial<Record<StatusInterno, EventoSaipos>> = {
  ACEITA: "ACCEPTED",
  RETIRADA: "ORDER_PICKED",
  EM_ENTREGA: "DELIVERY_ONGOING",
  ENTREGUE: "DELIVERY_FINISHED",
  REJEITADA: "REJECTED",
  CANCELADA: "CANCELLED",
};
