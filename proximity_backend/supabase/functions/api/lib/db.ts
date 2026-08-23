import { drizzle } from "npm:drizzle-orm/postgres-js";
import postgres from "npm:postgres";

import * as schema from "../db/schema.ts";

// Supavisor transaction-mode pooler (port 6543), service-role connection --
// same shape as Baker Ally's lib/db.ts. This is a privileged connection: it
// bypasses RLS entirely, which is why every route handler in this codebase
// does its own `WHERE user_id = authUser.id` / `WHERE shop_id IN (...)`
// filtering in TypeScript rather than relying on RLS to scope the query.
// See SPRINT_PLANNING.md §5.1 for the full reasoning (corrected there during
// Sprint 1 after this connection shape was confirmed) and
// migrations/005_rpc_set_default_address.sql for why RPC functions called
// from this connection take an explicit p_user_id rather than reading
// auth.uid().
const client = postgres(Deno.env.get("DB_POOL_URL")!, { prepare: false });

export const db = drizzle(client, { schema });
