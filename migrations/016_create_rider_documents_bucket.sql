-- Sprint 2: the `rider-documents` Storage bucket + its RLS policies --
-- named in SPRINT_PLANNING.md §3.6 ("private -- KYC docs for rider
-- onboarding") but never actually created by any migration through
-- Sprint 1. Needed now because migrations/011's design decision (KYC
-- upload goes Flutter -> Supabase Storage directly, not proxied through
-- the Edge Function) is only safe if this bucket exists and is genuinely
-- private -- without it, "private" was just a comment, not an enforced
-- property.
--
-- Storage's RLS is a live enforcement path, not a backstop like §5.1's
-- table policies -- Storage requests go through Supabase's Storage API
-- with the caller's real JWT, so auth.uid() is populated correctly there
-- (unlike the Edge Function's own service-role pooler connection). This is
-- the one place in this sprint where RLS is the actual security boundary,
-- not just defense in depth.
--
-- Convention: object path is `{user_id}/{filename}` -- storage.foldername()
-- splits on '/', so (storage.foldername(name))[1] is the uid segment. A
-- rider can only read/write their own folder; an admin can read (not
-- write) any folder, to actually review the document before approving
-- (routes/admin.ts's POST /admin/riders/:id/approve).

INSERT INTO storage.buckets (id, name, public)
VALUES ('rider-documents', 'rider-documents', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY rider_documents_insert_own ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'rider-documents' AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY rider_documents_select_own ON storage.objects
  FOR SELECT USING (
    bucket_id = 'rider-documents' AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY rider_documents_update_own ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'rider-documents' AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY rider_documents_delete_own ON storage.objects
  FOR DELETE USING (
    bucket_id = 'rider-documents' AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Admin review access -- read-only, deliberately no admin write/delete
-- policy (an admin correcting/replacing a rider's own KYC document isn't a
-- real workflow; if a document is wrong, the rider re-uploads via the same
-- own-folder path, which overwrites via rpc_create_rider_profile's
-- idempotent resubmit, migrations/015).
CREATE POLICY rider_documents_select_admin ON storage.objects
  FOR SELECT USING (
    bucket_id = 'rider-documents' AND public.get_role() = 'admin'
  );
