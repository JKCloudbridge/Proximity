import { createClient } from "./supabase/server";
import { request, ApiError } from "./api-core";

export { ApiError };

/** Server Components/Actions -- reads the session from cookies via
 *  next/headers, so this module must never be imported from a Client
 *  Component (see api-core.ts's comment). */
export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  return request<T>(path, session?.access_token, init);
}
