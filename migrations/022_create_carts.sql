-- Sprint 6: carts -- SPRINT_PLANNING.md §1.5 gives cart_items' literal DDL
-- directly but not this table's ("you'll need to design that table's own
-- DDL (owner FK, timestamps) against the surrounding prose" -- this sprint's
-- own instructions). Same "fresh design against prose, not a transcription
-- of a v1 original this repo's history can't recover" situation Sprint 3's
-- products/variants (017) and Sprint 5's wishlists (021) both hit -- except
-- here the actual v1 DDL turned out to be recoverable after all, just not
-- from *this* repo: the read-only Baker Ally reference project
-- (`C:\Users\hemin\Desktop\Android Project\migrations\014_create_carts.sql`)
-- has it, predating this project and matching §1.5's own "one active cart
-- per user, server is the source of truth" framing exactly. Reused directly
-- rather than re-derived from scratch -- one addition (`updated_at`) beyond
-- Baker Ally's literal file, so "remove all from this shop" and quantity
-- edits (routes/cart.ts) have a real column to bump, matching every other
-- mutable table in this codebase (shops, products, product_variants all
-- have both timestamps; carts is the one own-user-data table that mutates
-- after creation without ever getting a fresh row, unlike addresses/
-- wishlists which only ever insert/delete rows).
--
-- Deliberately NOT reusing Baker Ally's Drift-backed "two-layer" cart
-- architecture SPRINT_PLANNING.md §9's reuse map names (offline-first local
-- cache, guest cart merge-on-login, optimistic writes with revert-on-
-- failure) -- see routes/cart.ts's own header for why. One cart per user
-- (UNIQUE user_id), created lazily on first add-to-cart, never on signup --
-- same "own-user data materializes on first real interaction" precedent as
-- addresses' own first-row-is-default handling.

CREATE TABLE IF NOT EXISTS carts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE carts ENABLE ROW LEVEL SECURITY;

-- Own-user data (§5.2), same RLS shape as addresses/wishlists -- a backstop
-- only (§5.1), not the live enforcement (routes/cart.ts's authMiddleware +
-- explicit user_id filtering is that).
CREATE POLICY carts_all_own ON carts
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
