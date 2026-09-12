import type { GatewayId, PaymentGateway } from "./types.ts";
import { RazorpayGateway, readRazorpayConfigFromEnv } from "./razorpay.ts";
import { PayUGateway } from "./payu.ts";

export type { GatewayId, PaymentGateway, PaymentWebhookEvent } from "./types.ts";
export { GatewayNotImplementedError } from "./payu.ts";

// Sprint 8 -- §1.4's "swapping or running both becomes a config flag, not a
// rewrite," realized. routes/payments.ts never imports RazorpayGateway or
// PayUGateway directly -- it asks this file for "the gateway," and this file
// decides which one from PAYMENT_GATEWAY_DEFAULT (.env.example).
//
// Thrown, not returned as null, when Razorpay is selected but its three env
// vars aren't all set -- a misconfigured gateway on the only sprint that
// needs one to actually work is a deploy-time mistake worth failing loudly
// on, not a silent no-op.
export class PaymentGatewayNotConfiguredError extends Error {
  constructor(gateway: string) {
    super(`PAYMENT_GATEWAY_NOT_CONFIGURED:${gateway}`);
  }
}

export function getPaymentGateway(id?: GatewayId): PaymentGateway {
  const resolved = id ?? ((Deno.env.get("PAYMENT_GATEWAY_DEFAULT") as GatewayId | undefined) ?? "razorpay");

  if (resolved === "razorpay") {
    const config = readRazorpayConfigFromEnv();
    if (!config) throw new PaymentGatewayNotConfiguredError("razorpay");
    return new RazorpayGateway(config);
  }
  if (resolved === "payu") {
    return new PayUGateway();
  }
  throw new PaymentGatewayNotConfiguredError(resolved);
}
