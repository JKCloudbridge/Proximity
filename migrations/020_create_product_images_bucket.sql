-- Sprint 3: the `product-images` Storage bucket + its RLS policies --
-- named in SPRINT_PLANNING.md §3.6 alongside `shop-logos`/`shop-media`,
-- created now because this is the first sprint that actually needs it.
-- Unlike `rider-documents` (016) and `invoices`, §3.6 does NOT list this
-- bucket as private -- product photos are meant to be publicly viewable
-- (the buyer app renders them straight from their Storage URL, no signed-URL
-- round trip, same reasoning a product photo isn't sensitive the way a KYC
-- document is).
--
-- Convention: object path is `{shop_id}/{filename}` -- NOT `{user_id}/...`
-- like rider-documents, because ownership here is shop-scoped (any
-- owner/staff team member uploads on the shop's behalf, §5.3), not
-- individual-user-scoped. (storage.foldername(name))[1] is the shop_id
-- segment; RLS checks it against shop_team_members the same way every
-- product/product_images table policy above does. Comparison casts the
-- trusted side (shop_id::text), not the untrusted path segment (::uuid) --
-- same direction rider_documents' policies (016) cast auth.uid()::text
-- rather than the folder segment. Casting attacker-controlled path text to
-- uuid would raise a hard Postgres error on any malformed segment instead
-- of a clean "no match"; comparing as text degrades to an ordinary denied
-- policy either way.
--
-- Upload path: proximity_web's browser client uploads directly to Storage
-- (already-authenticated session, same "Storage is a separate,
-- already-authenticated path" precedent as the rider KYC upload, Sprint 2)
-- and then POSTs the resulting public URL to
-- POST /v1/shop/shops/:shopId/products/:productId/images
-- (routes/catalog.ts) to record the product_images row -- the Edge Function
-- itself never touches the image bytes.

INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS product_images_bucket_select_public ON storage.objects;
CREATE POLICY product_images_bucket_select_public ON storage.objects
  FOR SELECT USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS product_images_bucket_insert_team ON storage.objects;
CREATE POLICY product_images_bucket_insert_team ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] IN (
      SELECT shop_id::text FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff')
    )
  );

DROP POLICY IF EXISTS product_images_bucket_update_team ON storage.objects;
CREATE POLICY product_images_bucket_update_team ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] IN (
      SELECT shop_id::text FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff')
    )
  );

DROP POLICY IF EXISTS product_images_bucket_delete_team ON storage.objects;
CREATE POLICY product_images_bucket_delete_team ON storage.objects
  FOR DELETE USING (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] IN (
      SELECT shop_id::text FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff')
    )
  );
