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
import { serveLinkIntentRequest, linkIntentPathFromUrl, parseAllowedOrigins } from "./link-intent-http.ts";
import { createSupabaseAdminAuthPort, createSupabaseLinkIntentDataPort } from "./link-intent-port.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const moduleApiSecret = Deno.env.get("SEO_MODULE_API_SECRET") ?? "";

const client = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const port = createSupabaseSeoDataPort({
  rpc: (fn, args) => client.rpc(fn, args),
});

const linkIntentPort = createSupabaseLinkIntentDataPort({
  rpc: (fn, args) => client.rpc(fn, args),
});
const adminAuthPort = createSupabaseAdminAuthPort(client.auth.admin);

// Explicit SEO frontend origins for the browser-called provision path. Empty by
// default, which refuses every browser origin.
const allowedOrigins = parseAllowedOrigins(Deno.env.get("SEO_LINK_INTENT_ALLOWED_ORIGINS"));

const log = (event: Record<string, unknown>) => console.log(JSON.stringify(event));

Deno.serve((request: Request) => {
  // link-intent/* is a separate, non-Contract-v1 surface (see
  // link-intent-http.ts) and is routed here before anything Contract v1
  // specific runs, so it can never be reached through handleModuleRequest.
  const linkIntentPath = linkIntentPathFromUrl(request.url);
  if (linkIntentPath !== null) {
    return serveLinkIntentRequest(request, linkIntentPath, { moduleApiSecret, allowedOrigins }, {
      db: linkIntentPort,
      admin: adminAuthPort,
      log,
    });
  }

  return serveModuleRequest(request, { moduleApiSecret }, { db: port, log });
});
