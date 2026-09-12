-- Sprint 8: one column added to the existing `shops` table (§4.4), not a new
-- table -- GST invoices need a per-shop sequential number (§4.10: "under its
-- own GSTIN"), and the only honest way to hand out gapless-per-shop sequence
-- numbers under concurrent invoice generation is a row this project can lock
-- via a plain `UPDATE ... RETURNING`, same as any other counter column.
-- Postgres SEQUENCE objects are global-by-default and would need one CREATE
-- SEQUENCE per shop (or a shared sequence with no per-shop reset) -- a single
-- integer column on the row rpc_generate_invoice (037) already touches is
-- simpler and needs no per-shop DDL as shops are created.
--
-- Starts at 1, never reset -- this project's `discounts`/`orders`/etc. never
-- reset a counter by financial year either, and nothing in §4.10 asks for
-- one. If GST compliance later requires per-financial-year numbering, this
-- column is the thing that would need to become "seq, reset at April 1"
-- rather than a redesign.

ALTER TABLE shops ADD COLUMN IF NOT EXISTS next_invoice_seq INTEGER NOT NULL DEFAULT 1;
