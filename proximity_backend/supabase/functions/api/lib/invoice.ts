import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib";

import { supabaseAdmin } from "./supabaseAdmin.ts";

// Sprint 8 -- §5.4's rpc_generate_invoice "creates the invoices row + PDF."
// rpc_generate_invoice (migrations/037) does the row half; this file does
// the PDF half, since Postgres can't render one (that migration's own header
// explains the split). Uses `pdf-lib` (npm, v1.17.1 -- verified live against
// its actual npm listing before adding it, per this project's standing rule;
// last published some years ago but still the standard dependency-free
// JS/TS PDF library, with no native bindings to worry about inside a Deno
// Edge Function's V8 isolate -- flagged plainly in Sprint 8.md rather than
// silently treated as actively maintained).
//
// One real pdf-lib constraint this file works around, not just happens to
// avoid: `StandardFonts.Helvetica`/`HelveticaBold` only support WinAnsi
// encoding, which has NO glyph for the Rupee sign (U+20B9) -- pdf-lib throws
// at `drawText` time on an unencodable character, not a silent fallback
// glyph. Every amount here is rendered "Rs. 123.45," not "₹123.45," for
// exactly this reason (verified against pdf-lib's own font-embedding
// behavior, not assumed) -- an embedded custom font could add the real
// glyph later if this ever needs a polish pass.

const INVOICE_BUCKET = "invoices";
const PAGE_WIDTH = 595.28; // A4 in points
const PAGE_HEIGHT = 841.89;

export function formatRupees(paise: number): string {
  const sign = paise < 0 ? "-" : "";
  return `${sign}Rs. ${(Math.abs(paise) / 100).toFixed(2)}`;
}

export interface InvoicePdfLineItem {
  productName: string;
  variantName: string;
  quantity: number;
  unitPrice: number;
}

export interface InvoicePdfData {
  invoiceNumber: string;
  generatedAt: Date;
  orderId: string;
  shopName: string;
  shopGstin: string | null;
  buyerName: string | null;
  items: InvoicePdfLineItem[];
  subtotal: number;
  discountValue: number;
  deliveryFee: number;
  total: number;
}

/**
 * A deliberately plain, one-page invoice: seller name/GSTIN, invoice
 * number/date, buyer name, an itemized table, and the same subtotal/
 * discount/delivery/total breakdown §4.8's own orders row stores.
 *
 * **Real, disclosed limitation** (also flagged in migrations/034's header
 * and Sprint 8.md): no HSN codes, no CGST/SGST/IGST tax breakup. This
 * project's `products`/`product_variants` schema (Sprint 3) has no tax-rate
 * or HSN column anywhere to draw that breakup from -- this document records
 * what §4.10 actually asks for (a per-shop, per-order invoice under that
 * shop's own GSTIN) and nothing it doesn't have the underlying data to
 * support. Not a professionally reviewed GST-compliant template.
 */
export async function renderInvoicePdf(data: InvoicePdfData): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const bold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  const margin = 48;
  let y = PAGE_HEIGHT - margin;
  const black = rgb(0.13, 0.11, 0.1); // AppColors.ink, roughly

  const line = (text: string, opts: { size?: number; useBold?: boolean; x?: number } = {}) => {
    page.drawText(text, {
      x: opts.x ?? margin,
      y,
      size: opts.size ?? 11,
      font: opts.useBold ? bold : font,
      color: black,
    });
    y -= (opts.size ?? 11) + 6;
  };

  line(data.shopName, { size: 16, useBold: true });
  line(data.shopGstin ? `GSTIN: ${data.shopGstin}` : "GSTIN: not registered", { size: 10 });
  y -= 8;
  line(`Invoice ${data.invoiceNumber}`, { size: 13, useBold: true });
  line(`Date: ${data.generatedAt.toISOString().slice(0, 10)}`, { size: 10 });
  line(`Order: ${data.orderId}`, { size: 10 });
  y -= 6;
  line(`Bill to: ${data.buyerName ?? "Customer"}`, { size: 11 });
  y -= 10;

  // Table header
  const cols = { item: margin, qty: 340, unit: 400, total: 480 };
  line("Item", { useBold: true, x: cols.item });
  y += 17; // drawText already advanced y for "Item" -- put the rest of the header row on the same line
  page.drawText("Qty", { x: cols.qty, y, size: 11, font: bold, color: black });
  page.drawText("Unit", { x: cols.unit, y, size: 11, font: bold, color: black });
  page.drawText("Total", { x: cols.total, y, size: 11, font: bold, color: black });
  y -= 17;
  page.drawLine({ start: { x: margin, y: y + 10 }, end: { x: PAGE_WIDTH - margin, y: y + 10 }, thickness: 0.5, color: black });
  y -= 4;

  // Single page, no pagination -- a real, disclosed limitation (Sprint
  // 8.md), not handled this sprint: an order with enough line items to run
  // off the bottom of one A4 page (well past what a kirana-shop cart
  // realistically holds) would overlap the totals block rather than
  // flowing onto a second page. Revisit if a real shop's order size ever
  // approaches that.
  for (const item of data.items) {
    const label = `${item.productName} (${item.variantName})`;
    page.drawText(label.length > 46 ? `${label.slice(0, 43)}...` : label, { x: cols.item, y, size: 10, font, color: black });
    page.drawText(String(item.quantity), { x: cols.qty, y, size: 10, font, color: black });
    page.drawText(formatRupees(item.unitPrice), { x: cols.unit, y, size: 10, font, color: black });
    page.drawText(formatRupees(item.unitPrice * item.quantity), { x: cols.total, y, size: 10, font, color: black });
    y -= 16;
  }

  y -= 10;
  page.drawLine({ start: { x: margin, y: y + 10 }, end: { x: PAGE_WIDTH - margin, y: y + 10 }, thickness: 0.5, color: black });
  y -= 8;

  const totalsRow = (label: string, value: string, useBold = false) => {
    page.drawText(label, { x: cols.unit, y, size: 11, font: useBold ? bold : font, color: black });
    page.drawText(value, { x: cols.total, y, size: 11, font: useBold ? bold : font, color: black });
    y -= 16;
  };
  totalsRow("Subtotal", formatRupees(data.subtotal));
  if (data.discountValue > 0) totalsRow("Discount", `-${formatRupees(data.discountValue)}`);
  if (data.deliveryFee > 0) totalsRow("Delivery fee", formatRupees(data.deliveryFee));
  totalsRow("Total", formatRupees(data.total), true);

  y -= 20;
  line("This invoice does not include a CGST/SGST/IGST breakup or HSN codes --", { size: 8 });
  line("this project's catalog does not yet record a tax rate or HSN code per item.", { size: 8 });

  return pdfDoc.save();
}

/** `{shopId}/{orderId}.pdf` -- must match rpc_generate_invoice's own
 *  computation (migrations/037) exactly; kept as one function so the two
 *  never drift apart. */
export function invoicePdfPath(shopId: string, orderId: string): string {
  return `${shopId}/${orderId}.pdf`;
}

export async function uploadInvoicePdf(path: string, bytes: Uint8Array): Promise<void> {
  const { error } = await supabaseAdmin.storage.from(INVOICE_BUCKET).upload(path, bytes, {
    contentType: "application/pdf",
    upsert: true,
  });
  if (error) throw new Error(`INVOICE_UPLOAD_FAILED ${error.message}`);
}

export async function invoicePdfExists(path: string): Promise<boolean> {
  const lastSlash = path.lastIndexOf("/");
  const folder = path.slice(0, lastSlash);
  const filename = path.slice(lastSlash + 1);
  const { data, error } = await supabaseAdmin.storage.from(INVOICE_BUCKET).list(folder, { search: filename });
  if (error) return false;
  return (data ?? []).some((f) => f.name === filename);
}

/** Short-lived (§035's "a signed URL is the only way in") -- minted fresh on
 *  every read, never cached or stored, so a revoked/expired one never lingers
 *  in a client. */
export async function getInvoiceSignedUrl(path: string, expiresInSeconds = 300): Promise<string> {
  const { data, error } = await supabaseAdmin.storage.from(INVOICE_BUCKET).createSignedUrl(path, expiresInSeconds);
  if (error || !data) throw new Error(`INVOICE_SIGNED_URL_FAILED ${error?.message ?? "unknown"}`);
  return data.signedUrl;
}
