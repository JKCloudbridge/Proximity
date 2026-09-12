import { and, asc, eq, inArray, sql } from "npm:drizzle-orm";

import { db } from "./db.ts";
import { addresses, discounts, orderGroups, orderItems, orders, shops, users } from "../db/schema.ts";
import { invoicePdfExists, renderInvoicePdf, uploadInvoicePdf } from "./invoice.ts";

// Sprint 7/8 -- moved out of routes/checkout.ts (Sprint 7) into its own lib
// file this sprint specifically to give routes/payments.ts a second caller
// without a circular import between the two route files (payments.ts needs
// checkout.ts's loadOrderGroup; checkout.ts's own POST /orders handler now
// also needs Sprint 8's confirmPaymentAndGenerateInvoices, below) -- same
// "pull the shared thing out once a second caller exists" judgment call
// shopAccess.ts's isShopWriter made in Sprint 3.

/**
 * §7.4 step 5's confirmation-screen read: one order_group, its N per-shop
 * orders, their items, the shops/addresses/discount they reference. Used by
 * `GET /v1/order-groups/:id` (checkout.ts) and, new this sprint, by
 * routes/payments.ts's verify-payment handler (the buyer's app wants the
 * freshly-confirmed state back in the same response, not a second round
 * trip).
 */
export async function loadOrderGroup(groupId: string, userId: string) {
  const [group] = await db
    .select()
    .from(orderGroups)
    .where(and(eq(orderGroups.id, groupId), eq(orderGroups.userId, userId)))
    .limit(1);
  if (!group) return null;

  const orderRows = await db
    .select()
    .from(orders)
    .where(eq(orders.orderGroupId, groupId))
    .orderBy(asc(orders.createdAt));

  const orderIds = orderRows.map((o) => o.id);
  const itemRows = orderIds.length
    ? await db.select().from(orderItems).where(inArray(orderItems.orderId, orderIds))
    : [];

  const shopIds = [...new Set(orderRows.map((o) => o.shopId))];
  const shopRows = shopIds.length
    ? await db.select({ id: shops.id, name: shops.name, logoUrl: shops.logoUrl, addressLine: shops.addressLine }).from(shops).where(inArray(shops.id, shopIds))
    : [];
  const shopById = new Map(shopRows.map((s) => [s.id, s]));

  const addressIds = [...new Set(orderRows.map((o) => o.addressId).filter((id): id is string => id !== null))];
  const addressRows = addressIds.length
    ? await db.select().from(addresses).where(inArray(addresses.id, addressIds))
    : [];
  const addressById = new Map(addressRows.map((a) => [a.id, a]));

  const [discount] = group.discountId
    ? await db.select({ code: discounts.code, name: discounts.name }).from(discounts).where(eq(discounts.id, group.discountId)).limit(1)
    : [undefined];

  return {
    id: group.id,
    paymentMode: group.paymentMode,
    paymentStatus: group.paymentStatus,
    paymentGateway: group.paymentGateway,
    subtotal: group.subtotal,
    discountValue: group.discountValue,
    deliveryFeeTotal: group.deliveryFeeTotal,
    total: group.total,
    createdAt: group.createdAt,
    discount: discount ? { code: discount.code, name: discount.name } : null,
    orders: orderRows.map((o) => {
      const address = o.addressId ? addressById.get(o.addressId) : undefined;
      return {
        id: o.id,
        shop: shopById.get(o.shopId) ?? null,
        fulfillmentType: o.fulfillmentType,
        deliveryFulfilledBy: o.deliveryFulfilledBy,
        slotStart: o.slotStart,
        slotEnd: o.slotEnd,
        status: o.status,
        subtotal: o.subtotal,
        discountValue: o.discountValue,
        deliveryFee: o.deliveryFee,
        total: o.total,
        address: address ? { id: address.id, label: address.label, line1: address.line1, city: address.city } : null,
        items: itemRows
          .filter((i) => i.orderId === o.id)
          .map((i) => ({
            id: i.id,
            productName: i.productName,
            variantName: i.variantName,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
          })),
      };
    }),
  };
}

// Raw snake_case row shape `rpc_generate_invoice` returns through
// `db.execute(sql...)` -- same landmine every raw-SQL RPC call in this
// codebase has hit since rpc_set_default_address (Sprint 1); not re-shaped
// to camelCase here because nothing outside this file ever sees it.
interface RawInvoiceRow {
  id: string;
  order_id: string;
  shop_id: string;
  invoice_number: string;
  shop_name: string;
  shop_gstin: string | null;
  subtotal: number;
  discount_value: number;
  delivery_fee: number;
  total: number;
  pdf_path: string;
  generated_at: string;
}

/**
 * Generates (if missing) the DB row + PDF for one order. Idempotent both at
 * the DB layer (rpc_generate_invoice, migrations/037) and here (checks
 * `invoicePdfExists` before re-rendering/re-uploading) -- safe to call every
 * time a payment gets confirmed, including a second confirm attempt after a
 * first one's PDF step failed partway.
 */
async function ensureInvoiceForOrder(orderId: string): Promise<void> {
  const rows = (await db.execute(
    sql`SELECT * FROM public.rpc_generate_invoice(${orderId}::uuid)`,
  )) as unknown as RawInvoiceRow[];
  const invoiceRow = rows[0];
  if (!invoiceRow) return;

  if (await invoicePdfExists(invoiceRow.pdf_path)) return;

  const [order] = await db.select().from(orders).where(eq(orders.id, orderId)).limit(1);
  if (!order) return;

  const itemRows = await db.select().from(orderItems).where(eq(orderItems.orderId, orderId));
  const [buyer] = await db.select({ fullName: users.fullName }).from(users).where(eq(users.id, order.userId)).limit(1);

  const bytes = await renderInvoicePdf({
    invoiceNumber: invoiceRow.invoice_number,
    generatedAt: new Date(invoiceRow.generated_at),
    orderId,
    shopName: invoiceRow.shop_name,
    shopGstin: invoiceRow.shop_gstin,
    buyerName: buyer?.fullName ?? null,
    items: itemRows.map((i) => ({
      productName: i.productName,
      variantName: i.variantName,
      quantity: i.quantity,
      unitPrice: i.unitPrice,
    })),
    subtotal: invoiceRow.subtotal,
    discountValue: invoiceRow.discount_value,
    deliveryFee: invoiceRow.delivery_fee,
    total: invoiceRow.total,
  });

  await uploadInvoicePdf(invoiceRow.pdf_path, bytes);
}

/**
 * Sprint 8's one real write path for "a payment (or a pay-at-shop placement)
 * just got confirmed": calls rpc_confirm_payment (036), then generates an
 * invoice per order in the group. Three callers, one implementation:
 *   * routes/checkout.ts's POST /orders, for pay_at_shop groups, immediately
 *     after rpc_place_order succeeds (see migrations/036's header for why
 *     that's the chosen trigger point for 'collected_at_shop').
 *   * routes/payments.ts's verify-payment route, for the fast client-side
 *     confirmation path after a Razorpay Checkout success.
 *   * routes/payments.ts's webhook route, the authoritative online-path
 *     trigger.
 *
 * Invoice generation is deliberately best-effort per order: a PDF failure
 * for one shop's sub-order must not undo or re-fail the payment confirmation
 * that already committed, and must not block a sibling shop's own invoice.
 * Logged, not thrown -- routes/invoices.ts's own GET route self-heals a
 * missing PDF on demand (see that file), so a transient failure here isn't
 * permanent.
 */
export async function confirmPaymentAndGenerateInvoices(params: {
  groupId: string;
  gateway?: string | null;
  gatewayOrderId?: string | null;
  gatewayPaymentId?: string | null;
}): Promise<void> {
  await db.execute(sql`
    SELECT public.rpc_confirm_payment(
      ${params.groupId}::uuid,
      ${params.gateway ?? null},
      ${params.gatewayOrderId ?? null},
      ${params.gatewayPaymentId ?? null}
    )
  `);

  const orderRows = await db.select({ id: orders.id }).from(orders).where(eq(orders.orderGroupId, params.groupId));
  for (const row of orderRows) {
    try {
      await ensureInvoiceForOrder(row.id);
    } catch (err) {
      console.error(`Invoice generation failed for order ${row.id}`, err);
    }
  }
}
