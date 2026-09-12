import { createClient } from "npm:@supabase/supabase-js";

// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-provided inside every
// Edge Function -- do not set them manually. Used for verifying a bearer
// token in authMiddleware (supabaseAdmin.auth.getUser(token)), same pattern
// as Baker Ally's lib/supabaseAdmin.ts. Sprint 8 adds a second real use:
// lib/invoice.ts's Storage calls against the private `invoices` bucket --
// that bucket has no client-facing RLS read/write policy at all (035's own
// header), so the service-role client is the only thing that can ever touch
// it.
export const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
