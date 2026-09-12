import { Hono } from "npm:hono";
import { eq } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { invoices, orderItems, orders, users } from "../db/schema.ts";
import { isShopWriter } from "../lib/shopAccess.ts";
import { getInvoiceSignedUrl, invoicePdfExists, renderInvoicePdf, uploadInvoicePdf } from "../lib/invoice.ts";

// Sprint 8 -- §4.10's invoice, read back. Two ownership classes can read the
// same invoice (§5.3's "View sales summary / invoices" row is owner+staff;
// the buyer who placed the order is the other), same two-class shape
// invoices' own RLS backstop declares (migrations/034) -- checked here, in
// the Edge Function, which is the actual trust boundary (§5.1).
//
// Never returns `pdf_path` itself -- only a short-lived signed URL, minted
// fresh on every request (migrations/035's own header: "a signed URL is the
// only way in"). The URL is deliberately not cached anywhere server-side.
export const invoicesRoute = new Hono<AuthEnv>();

invoicesRoute.use("/orders/*", authMiddleware);

invoicesRoute.get("/orders/:orderId/invoice", async (c) => {
  const authUser = c.get("user");
  const orderId = c.req.param("orderId");

  const [order] = await db.select().from(orders).where(eq(orders.id, orderId)).limit(1);
  if (!order) return c.json({ error: { code: "ORDER_NOT_FOUND", message: "Order not found" } }, 404);

  const isBuyer = order.userId === authUser.id;
  if (!isBuyer && !(await isShopWriter(authUser.id, order.shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "You can't view this invoice" } }, 403);
  }

  const [invoice] = await db.select().from(invoices).where(eq(invoices.orderId, orderId)).limit(1);
  if (!invoice) {
    // Not generated yet -- either the order genuinely isn't confirmed yet
    // (rpc_generate_invoice refuses a pending/cancelled order,
    // migrations/037), or invoice generation itself never ran for some
    // reason. Either way, a 404 here is honest: there is no document to
    // hand back right now, and this route doesn't generate one speculatively
    // for an order that was never confirmed.
    return c.json({ error: { code: "INVOICE_NOT_FOUND", message: "No invoice yet for this order" } }, 404);
  }

  // Self-healing: the row can exist with no PDF behind it if a prior
  // generation's upload step failed (lib/orderConfirmation.ts's own
  // best-effort, logged-not-thrown handling). Rather than surface that as a
  // permanent 404 to whoever asks next, regenerate the bytes from the row's
  // own already-fixed data and try the upload again.
  if (!(await invoicePdfExists(invoice.pdfPath))) {
    const itemRows = await db.select().from(orderItems).where(eq(orderItems.orderId, orderId));
    const [buyer] = await db.select({ fullName: users.fullName }).from(users).where(eq(users.id, order.userId)).limit(1);

    const bytes = await renderInvoicePdf({
      invoiceNumber: invoice.invoiceNumber,
      generatedAt: invoice.generatedAt,
      orderId,
      shopName: invoice.shopName,
      shopGstin: invoice.shopGstin,
      buyerName: buyer?.fullName ?? null,
      items: itemRows.map((i) => ({
        productName: i.productName,
        variantName: i.variantName,
        quantity: i.quantity,
        unitPrice: i.unitPrice,
      })),
      subtotal: invoice.subtotal,
      discountValue: invoice.discountValue,
      deliveryFee: invoice.deliveryFee,
      total: invoice.total,
    });

    try {
      await uploadInvoicePdf(invoice.pdfPath, bytes);
    } catch (err) {
      console.error(`Invoice regeneration failed for order ${orderId}`, err);
      return c.json({ error: { code: "INVOICE_UNAVAILABLE", message: "Could not prepare this invoice -- try again shortly" } }, 502);
    }
  }

  const url = await getInvoiceSignedUrl(invoice.pdfPath);
  return c.json({
    data: {
      invoiceNumber: invoice.invoiceNumber,
      generatedAt: invoice.generatedAt,
      total: invoice.total,
      url,
    },
  });
});
