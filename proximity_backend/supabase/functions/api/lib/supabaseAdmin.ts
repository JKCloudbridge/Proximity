import { createClient } from "npm:@supabase/supabase-js";

// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-provided inside every
// Edge Function -- do not set them manually. Used for exactly one thing in
// this codebase: verifying a bearer token in authMiddleware
// (supabaseAdmin.auth.getUser(token)). Same pattern as Baker Ally's
// lib/supabaseAdmin.ts.
export const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
