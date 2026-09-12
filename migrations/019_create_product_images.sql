-- Sprint 3: product_images -- an ordered photo list per product, same
-- relationship shop_media (009) has to shops. Kept as its own table rather
-- than a single `image_url` column on `products` because a PDP (§7,
-- Sprint 5) needs a gallery, not one photo -- and because the upload path
-- (direct browser -> Supabase Storage, see migrations/020's bucket) writes
-- rows here independently of the product-edit form save.

CREATE TABLE IF NOT EXISTS product_images (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  image_url   TEXT NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_images_product_id ON product_images(product_id);

ALTER TABLE product_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY product_images_select_public ON product_images
  FOR SELECT USING (
    product_id IN (
      SELECT id FROM products
      WHERE is_active = true AND shop_id IN (SELECT id FROM shops WHERE status = 'approved')
    )
  );

CREATE POLICY product_images_select_team ON product_images
  FOR SELECT USING (
    product_id IN (
      SELECT id FROM products WHERE shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
    )
  );

-- Owner + staff (§5.3), same as products/product_variants above.
CREATE POLICY product_images_team_write ON product_images
  FOR ALL USING (
    product_id IN (
      SELECT id FROM products
      WHERE shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff'))
    )
  )
  WITH CHECK (
    product_id IN (
      SELECT id FROM products
      WHERE shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff'))
    )
  );

CREATE POLICY product_images_admin_all ON product_images
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
