import type {
  CreateGatewayOrderParams,
  CreateGatewayOrderResult,
  PaymentGateway,
  PaymentWebhookEvent,
  VerifyPaymentSignatureParams,
} from "./types.ts";

// Sprint 8 -- the PayU stub §1.4/§11 explicitly ask for: "keep a PayU
// adapter as a stub." SPRINT_PLANNING.md §13's open-decisions log said
// "confirm current Flutter-SDK-maturity ... before Sprint 8 starts" -- that
// confirmation never happened (no PayU test/sandbox credentials exist for
// this project, and this sprint's own write-up says so plainly rather than
// guessing at PayU's current package maturity from training-data memory,
// per this project's standing rule for third-party integrations). This
// class exists so `lib/payments/index.ts`'s registry is real (a genuine
// second entry, not a comment saying "add one later") and so
// PAYMENT_GATEWAY_DEFAULT=payu fails loudly and specifically rather than
// crashing on a missing method somewhere deep in routes/payments.ts.
//
// Every method throws the same typed error -- routes/payments.ts maps it to
// a 501, not a 500, the same "this is a known, named gap, not a crash"
// distinction PLACE_ORDER_ERRORS already draws for rpc_place_order's typed
// codes.
export class GatewayNotImplementedError extends Error {
  constructor(gateway: string) {
    super(`GATEWAY_NOT_IMPLEMENTED:${gateway}`);
  }
}

export class PayUGateway implements PaymentGateway {
  readonly id = "payu" as const;

  createOrder(_params: CreateGatewayOrderParams): Promise<CreateGatewayOrderResult> {
    throw new GatewayNotImplementedError("payu");
  }

  verifyPaymentSignature(_params: VerifyPaymentSignatureParams): Promise<boolean> {
    throw new GatewayNotImplementedError("payu");
  }

  verifyAndParseWebhook(_rawBody: string, _signatureHeader: string | undefined): Promise<PaymentWebhookEvent | null> {
    throw new GatewayNotImplementedError("payu");
  }
}
