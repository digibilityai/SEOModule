import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { WorkerConfig } from "./config.js";

// Service-role client — SERVER-SIDE ONLY. Bypasses RLS by design; used solely to
// call the service-role-only worker lifecycle RPCs. Never constructed in the
// frontend; the key comes only from server-side env.
export function createWorkerSupabase(cfg: WorkerConfig): SupabaseClient {
  return createClient(cfg.supabaseUrl, cfg.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
