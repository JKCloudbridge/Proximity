-- Sprint 6: product_cross_sell -- SPRINT_PLANNING.md §4.10 says this table
-- "carries over unchanged from v1" without repeating its DDL, and (same
-- situation products/product_variants/product_images hit in Sprint 3 and
-- wishlists hit in Sprint 5) that v1 pass predates this repo's git history.
-- Unlike wishlists (021), the actual original turned out to be recoverable
-- this time -- not from this repo, but from the read-only Baker Ally
-- reference project (`C:\Users\hemin\Desktop\Android Project\migrations\
-- 025_AP_product_cross_sell.sql`), which §9's reuse map already names as
-- where this table's design came from. Reused directly rather than
-- re-derived from prose alone, one addition beyond that literal file (the
-- self-reference CHECK below) flagged plainly rather than silently folded
-- in, same "documented addition, not a silent deviation" discipline as
-- migrations/011's kyc_document_url.
--
-- Admin-curated (§8.6 lists "discount authoring" as this sprint's admin
-- scope neighbor; cross-sell curation isn't itemized there or anywhere else
-- in §8.6 -- honestly flagging that this table has no admin route to
-- populate it yet, same "table only, no route yet" situation shop_media/
-- shop_blackout_dates sat in through Sprints 2-5). Until that curation UI
-- exists, routes/recommendations.ts's personalized path (source products ->
-- this table) always returns zero rows in practice; the trending fallback
-- (§11's Sprint 6 entry names it explicitly) is what actually powers
-- Recommended-for-you until then -- see that route file's own header.

CREATE TABLE IF NOT EXISTS product_cross_sell (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_product_id       UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  recommended_product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  sort_order              INTEGER NOT NULL DEFAULT 0,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source_product_id, recommended_product_id),
  -- Not in Baker Ally's original -- a product recommending itself is never
  -- meaningful, and nothing else in the schema stops it (both columns just
  -- FK to the same table). Flagged here rather than silently added.
  CHECK (source_product_id <> recommended_product_id)
);

CREATE INDEX IF NOT EXISTS idx_product_cross_sell_source ON product_cross_sell(source_product_id, sort_order);

ALTER TABLE product_cross_sell ENABLE ROW LEVEL SECURITY;

-- Public read (anyone browsing, logged in or not -- same shape as
-- categories, 003), admin-only write via the same get_role() helper (004).
-- No route reads or writes this yet either way (see header) -- RLS is
-- written now so it's correct the moment a route does exist, same
-- "policy alongside the table, not bolted on later" discipline every prior
-- migration in this project has followed.
CREATE POLICY product_cross_sell_select_all ON product_cross_sell
  FOR SELECT USING (true);

CREATE POLICY product_cross_sell_admin_write ON product_cross_sell
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
