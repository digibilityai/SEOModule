/**
 * Deno entry point for the seo-module-api Edge Function.
 *
 * Intentionally the thinnest possible shell: read configuration, build the
 * service-role client, delegate. Every decision worth testing lives in
 * handler.ts, http.ts, supabase-port.ts and normalize-host.ts, which are plain
 * TypeScript with no Deno dependency and are covered by vitest.
 *
 * The SEO service-role key is read from the function's own environment and is
 * never returned, logged or echoed. This function is the only place it is used,
 * and it is server to server only: the browser application continues to use the
 * anon key and RLS, unchanged.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.50.3";
import { createSupabaseSeoDataPort } from "./supabase-port.ts";
import { serveModuleRequest } from "./http.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const moduleApiSecret = Deno.env.get("SEO_MODULE_API_SECRET") ?? "";

const client = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const port = createSupabaseSeoDataPort({
  rpc: (fn, args) => client.rpc(fn, args),
});

Deno.serve((request: Request) =>
  serveModuleRequest(request, { moduleApiSecret }, {
    db: port,
    log: (event) => console.log(JSON.stringify(event)),
  })
);
