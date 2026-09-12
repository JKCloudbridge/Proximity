import { createBrowserClient } from "@supabase/ssr";

// Used from Client Components (login/signup forms, etc.) -- same
// NEXT_PUBLIC_ env vars as server.ts/proxy.ts. Ported structurally from
// baker_ally_admin/lib/supabase/client.ts (SPRINT_PLANNING.md §9 reuse map
// -- this exact Next.js 16 + @supabase/ssr wiring is already proven there).
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
