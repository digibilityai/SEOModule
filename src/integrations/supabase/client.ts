import { createClient } from "@supabase/supabase-js";
import { getSupabaseAnonKey, getSupabaseUrl } from "@/config/runtimeConfig";

// Points at the dedicated SEO Supabase project. In production, Digibility Core
// remains the upstream identity provider and the one-time bridge establishes a
// normal refreshable session in this project. TEST/local standalone auth stays
// available when bridge configuration is intentionally absent.
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
