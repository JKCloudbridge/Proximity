-- Sprint 3: products -- SPRINT_PLANNING.md §4.5: "products (shop-scoped,
-- is_veg, info_message, search vector) ... carry over exactly as designed
-- in v1." §4.5 itself doesn't repeat v1's literal DDL (it says so
-- explicitly -- "pull it from the v1 content already discussed if you need
-- it restated"), and that v1 pass isn't present in this repo's history
-- (the planning doc's v1->v2 rewrite predates git), so this migration is a
-- fresh design against the *prose* spec, built with the same conventions
-- every other table here already uses (UUID PKs, paise-integer money on
-- the variants table below, RLS-on-everything, the shop_sub_categories
-- (010)/shop_media (009) four-policy shape).
--
-- `category_id` is required (every product sits under one of the 20 global
-- categories, §4.3 -- this is what powers cross-shop category filtering on
-- the buyer Home, Sprint 4). `sub_category_id` is optional -- a shop can
-- list products before it's bothered to define its own rail entries
-- (§4.3's shop_sub_categories, 010), same "onboarding shouldn't block on
-- optional structure" reasoning shops.ts already applies to business hours.
-- Sub-category, when set, must belong to the same shop AND the same
-- top-level category -- enforced in routes/catalog.ts (not a CHECK
-- constraint here: it's a cross-table invariant, and this backend's own
-- convention, per SPRINT_PLANNING.md §5.1, is that RLS is a backstop, not
-- the live enforcement layer -- the Edge Function route is).
--
-- `is_veg` is nullable, not NOT NULL DEFAULT false -- §4.3's FSSAI-labelling
-- note only applies to food categories; a Hardware & Tools product has no
-- veg/non-veg meaning at all, and defaulting it to `false` would print a
-- green dot on a screwdriver. NULL = "not applicable," not "unknown."
--
-- `info_message` is a freeform shopkeeper note (e.g. "contains nuts",
-- "ships in 2 days") -- distinct from `description`, which is the product's
-- own marketing copy.
--
-- `search_vector` is a STORED generated column, not a trigger -- the
-- to_tsvector('english', <literal columns>) shape is Postgres's own
-- documented example for exactly this (generated columns require an
-- immutable expression, and a fixed 'english' config literal qualifies).
-- No route reads it yet (search lands with buyer browse, Sprint 4+) -- the
-- column and its index exist now so the table doesn't need a later
-- migration just to add search support, same "don't block a future sprint
-- on a schema change" reasoning as shop_blackout_dates (013).

CREATE TABLE IF NOT EXISTS products (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id          UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  category_id      UUID NOT NULL REFERENCES categories(id),
  sub_category_id  UUID REFERENCES shop_sub_categories(id) ON DELETE SET NULL,
  name             TEXT NOT NULL,
  description      TEXT,
  is_veg           BOOLEAN,
  info_message     TEXT,
  is_active        BOOLEAN NOT NULL DEFAULT true,
  search_vector    TSVECTOR GENERATED ALWAYS AS (
                      to_tsvector('english', coalesce(name, '') || ' ' || coalesce(description, ''))
                   ) STORED,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_products_shop_id ON products(shop_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_sub_category_id ON products(sub_category_id);
CREATE INDEX IF NOT EXISTS idx_products_search_vector ON products USING GIN(search_vector);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Buyer browsing (Sprint 4+) only ever sees active products from approved
-- shops -- same shape as shops_select_public (006) and
-- shop_sub_categories_select_public (010). Backstop only (§5.1); the actual
-- buyer-facing route in routes/catalog.ts filters on both conditions itself
-- too.
CREATE POLICY products_select_public ON products
  FOR SELECT USING (
    is_active = true AND shop_id IN (SELECT id FROM shops WHERE status = 'approved')
  );

CREATE POLICY products_select_team ON products
  FOR SELECT USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
  );

-- Owner + staff manage the catalog (§5.3's "Add/edit catalog" row) --
-- delivery-role members get no write access here at all.
CREATE POLICY products_team_write ON products
  FOR ALL USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff'))
  )
  WITH CHECK (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff'))
  );

CREATE POLICY products_admin_all ON products
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
