-- Sprint 8: rpc_generate_invoice(order_id) -- §5.4: "system, triggered on
-- orders.status -> confirmed. Creates the invoices row + PDF." Split exactly
-- the way this project has split every prior "Postgres can't do X" case
-- (RLS can't verify a webhook signature, §5.1; a GEOGRAPHY column has no
-- clean Drizzle type, schema.ts's header): **this function creates and
-- returns the invoice's row and its metadata only.** Postgres cannot render
-- a PDF -- the actual bytes are generated and uploaded to the private
-- `invoices` bucket (035) by lib/invoice.ts (pdf-lib), immediately after this
-- RPC returns, in the same request that called rpc_confirm_payment (036) --
-- see routes/payments.ts's webhook/verify-payment handlers for exactly where
-- that call sits. `pdf_path` is computed here, deterministically
-- (`{shop_id}/{order_id}.pdf`), specifically so the TS layer never has to
-- round-trip a generated path back into this table -- it already knows
-- exactly where to upload before it starts building the PDF.
--
-- Idempotent, same reasoning as every other RPC this project calls more than
-- once per real-world event (rpc_add_to_cart's upsert, rpc_confirm_payment's
-- FOR UPDATE guard above): calling this twice for the same order_id (a retry
-- after a partial failure -- the DB row committed but the PDF upload that
-- follows it in routes/payments.ts threw) returns the SAME row rather than
-- erroring or minting a second invoice number, so the TS layer can safely
-- call this again and re-attempt just the PDF upload against the row's
-- already-fixed pdf_path. See migrations/033's header for why the sequence
-- number itself is a per-shop counter column rather than a SQL SEQUENCE.
--
-- One honest, disclosed rough edge: the ON CONFLICT DO NOTHING guard below
-- (for the rare case of two concurrent calls for the same brand-new
-- order_id) means a losing concurrent call still burns a `next_invoice_seq`
-- value that never appears on any real invoice -- a small gap in the
-- numbering, not a duplicate or a lost invoice. Nothing in §4.10 requires
-- gapless numbering (only "under its own GSTIN"), so this wasn't engineered
-- away with a heavier lock; flagged here rather than silently accepted.
--
-- Refuses to generate against an order that was never confirmed
-- (status='pending') or was cancelled -- an invoice for money that was never
-- actually confirmed as owed is a real document with legal weight (§4.10),
-- not a receipt draft.

CREATE OR REPLACE FUNCTION public.rpc_generate_invoice(p_order_id UUID)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing public.invoices%ROWTYPE;
  v_order    public.orders%ROWTYPE;
  v_shop     public.shops%ROWTYPE;
  v_seq      INTEGER;
  v_number   TEXT;
  v_path     TEXT;
  v_invoice  public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO v_existing FROM public.invoices WHERE order_id = p_order_id;
  IF FOUND THEN
    RETURN v_existing;
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND' USING ERRCODE = 'P0030';
  END IF;

  IF v_order.status IN ('pending', 'cancelled') THEN
    RAISE EXCEPTION 'ORDER_NOT_CONFIRMED' USING ERRCODE = 'P0031';
  END IF;

  SELECT * INTO v_shop FROM public.shops WHERE id = v_order.shop_id;

  -- Atomic per-shop counter (migrations/033) -- the UPDATE's own row lock
  -- serializes concurrent invoice generation for the SAME shop; see header
  -- for the (much rarer, harmless) same-order_id race this doesn't cover.
  UPDATE public.shops
  SET next_invoice_seq = next_invoice_seq + 1
  WHERE id = v_shop.id
  RETURNING next_invoice_seq - 1 INTO v_seq;

  v_number := 'INV-' || upper(substr(replace(v_shop.id::text, '-', ''), 1, 8)) || '-' || lpad(v_seq::text, 6, '0');
  v_path   := v_shop.id::text || '/' || p_order_id::text || '.pdf';

  INSERT INTO public.invoices (
    order_id, shop_id, invoice_number, shop_name, shop_gstin,
    subtotal, discount_value, delivery_fee, total, pdf_path
  ) VALUES (
    p_order_id, v_shop.id, v_number, v_shop.name, v_shop.gstin,
    v_order.subtotal, v_order.discount_value, v_order.delivery_fee, v_order.total, v_path
  )
  ON CONFLICT (order_id) DO NOTHING
  RETURNING * INTO v_invoice;

  IF v_invoice.id IS NULL THEN
    SELECT * INTO v_invoice FROM public.invoices WHERE order_id = p_order_id;
  END IF;

  RETURN v_invoice;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_generate_invoice(UUID) FROM authenticated, anon, public;
