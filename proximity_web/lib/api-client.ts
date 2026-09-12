import { createClient as createBrowserSupabaseClient } from "./supabase/client";
import { request, ApiError } from "./api-core";

export { ApiError };

/** Client Components -- browser-side session lookup, safe to bundle for the
 *  browser (no next/headers import in this module's graph). */
export async function apiFetchClient<T>(path: string, init?: RequestInit): Promise<T> {
  const supabase = createBrowserSupabaseClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  return request<T>(path, session?.access_token, init);
}
