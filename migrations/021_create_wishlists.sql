-- Sprint 5: wishlists -- SPRINT_PLANNING.md §4.10: "wishlists ... carry over
-- unchanged from v1" without repeating its DDL, and (same situation
-- products/product_variants/product_images hit in Sprint 3, see
-- migrations/017's header comment) that v1 pass predates this repo's git
-- history and isn't recoverable from anywhere in this project. So this is a
-- fresh design against the prose spec, not a transcription of an original
-- that no longer exists -- flagging that plainly, same as 017 did.
--
-- Scoped to the product as a whole, not one specific product_variant -- a
-- buyer saves "this snack" to come back to later, not "this snack in the
-- 200g size specifically." The variant picker still lives on the PDP
-- (§7.1's shop-detail/PDP spec, this sprint) for when they actually go to
-- buy it. Own-user data (§5.2's ownership-class table), same RLS shape as
-- addresses (002) -- no shop-team or admin policy needed, a wishlist row is
-- never shop- or admin-visible.

CREATE TABLE IF NOT EXISTS wishlists (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_wishlists_user_id ON wishlists(user_id);
CREATE INDEX IF NOT EXISTS idx_wishlists_product_id ON wishlists(product_id);

ALTER TABLE wishlists ENABLE ROW LEVEL SECURITY;

CREATE POLICY wishlists_all_own ON wishlists
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
