// Subconjunto do schema Open Delivery (DeliveryOrder) que o backend usa,
// com os nomes de campo exatamente como confirmados no openapi.yaml oficial
// da Abrasel (referenciado pela doc da Saipos). Não inclui todos os campos
// do spec — só os que a tela de Pedidos precisa mostrar nesta fase.

export interface Price {
  value: number; // decimal, ex.: 40 = R$ 40,00 (não é em centavos)
  currency: string;
}

export interface AddressLogistics {
  country: string;
  state: string;
  city: string;
  district: string;
  street: string;
  number: string;
  postalCode: string;
  complement: string;
  reference?: string;
  latitude?: number;
  longitude?: number;
}

export interface DeliveryOrderPayload {
  orderId: string; // UUID gerado pela Saipos
  orderDisplayId: string; // número exibido pro cliente
  merchant: { id: string; name: string };
  pickupAddress: AddressLogistics;
  deliveryAddress: AddressLogistics;
  customerName: string;
  specialInstructions?: string;
  confirmationCodeRequired?: boolean;
  totalOrderPrice: Price;
  orderDeliveryFee: Price;
  payments?: {
    method?: "OFFLINE" | "ONLINE";
    offlineMethod?: Array<{
      type: "CREDIT" | "DEBIT" | "MEAL_VOUCHER" | "FOOD_VOUCHER" | "PIX" | "CASH" | "CREDIT_DEBIT" | "OTHER";
      amount: Price;
    }>;
    change?: Price;
  };
}

export function formatarEndereco(addr: AddressLogistics): string {
  const partes = [`${addr.street}, ${addr.number}`, addr.district, addr.city, addr.state];
  if (addr.complement) partes.splice(1, 0, addr.complement);
  return partes.filter(Boolean).join(" - ");
}
