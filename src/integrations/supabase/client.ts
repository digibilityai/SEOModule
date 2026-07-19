import { createClient } from "@supabase/supabase-js";
import { getSupabaseAnonKey, getSupabaseUrl } from "@/config/runtimeConfig";

// Points at the SAME Supabase project as the main Digibility app, so SEO
// reuses Digibility's existing users/auth instead of a separate auth system.
//
// Frontend-safe by design: only the public URL + anon key are ever read here
// (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY). The service role key must
// NEVER be used in this file, or anywhere in frontend code — it belongs
// server-side only. VITE_ env vars are bundled into the client build and are
// publicly readable in the browser.
//
// createClient() throws synchronously on an empty/invalid URL, which would
// crash the whole app at import time before .env is configured. Fall back to
// a placeholder so the app still renders — this is what keeps mock mode
// working without any Supabase project at all. Auth/data calls simply won't
// resolve real data until real test-project credentials are set in .env and
// VITE_SEO_DATA_MODE=supabase (see src/config/runtimeConfig.ts and
// src/services/dataMode.ts).
const supabaseUrl = getSupabaseUrl() || "https://placeholder.supabase.co";
const supabaseAnonKey = getSupabaseAnonKey() || "placeholder-anon-key";

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
