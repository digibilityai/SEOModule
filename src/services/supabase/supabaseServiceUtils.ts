import { supabase } from "@/integrations/supabase/client";
import { hasSupabaseConfig } from "@/config/runtimeConfig";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

/**
 * Throws a clear, dev-facing error if Supabase is not configured. Call this
 * at the top of any future Supabase-backed service function before making a
 * request, so a missing/misconfigured .env produces one readable error
 * instead of a confusing network failure deep inside supabase-js.
 */
export function assertSupabaseConfigured(callerLabel: string): void {
  if (!hasSupabaseConfig()) {
    throw new Error(
      `${callerLabel}: Supabase is not configured (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY missing or invalid). ` +
        "Set VITE_SEO_DATA_MODE=mock, or provide valid test-project credentials in .env.",
    );
  }
}

/** Returns the current Supabase session's user id, or null if unauthenticated. Never throws. */
export async function getCurrentUserId(): Promise<string | null> {
  const { data, error } = await supabase.auth.getSession();
  if (error) {
    console.warn(
      "[supabaseServiceUtils] auth.getSession() failed:",
      normalizeSupabaseError(error).message,
    );
    return null;
  }
  return data.session?.user.id ?? null;
}

/**
 * Throws when no authenticated Supabase user is present. Use as a
 * defense-in-depth guard in services where unauthenticated access should
 * never even attempt a Supabase call — RLS on the database remains the
 * actual source of truth for authorization.
 */
export async function requireAuthenticatedUser(callerLabel: string): Promise<string> {
  const userId = await getCurrentUserId();
  if (!userId) {
    throw new Error(`${callerLabel}: no authenticated Supabase user (session missing).`);
  }
  return userId;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** True only for a well-formed UUID string — mock ids (e.g. "web_mock_001") never match. */
export function isValidUuid(value: string | null | undefined): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

/**
 * Throws when `value` isn't a valid UUID, before any Supabase query is
 * issued. Guards against passing a mock-mode id (e.g. "web_mock_001",
 * produced when an earlier call in the same chain already fell back to
 * mock) into a Supabase query — PostgREST would otherwise reject it with a
 * generic 400 ("invalid input syntax for type uuid") deep inside the
 * request instead of failing clearly and early.
 */
export function requireValidUuid(
  callerLabel: string,
  value: string | null | undefined,
  fieldName = "id",
): string {
  if (!isValidUuid(value)) {
    throw new Error(
      `${callerLabel}: ${fieldName} "${value ?? ""}" is missing or not a valid Supabase UUID.`,
    );
  }
  return value;
}

/**
 * Wraps a Supabase query expected to return zero-or-one row. Normalizes the
 * `{ data, error }` shape into a plain return value or a thrown Error with a
 * clear, labeled message, so callers don't repeat PostgREST error handling.
 */
export async function safeSingle<T>(
  callerLabel: string,
  query: PromiseLike<{ data: T | null; error: unknown }>,
): Promise<T | null> {
  const { data, error } = await query;
  if (error) {
    throw new Error(`${callerLabel}: ${normalizeSupabaseError(error).message}`);
  }
  return data;
}

/**
 * Wraps a Supabase query expected to return a list. Never returns null —
 * defaults to an empty array so callers can map/iterate safely.
 */
export async function safeList<T>(
  callerLabel: string,
  query: PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const { data, error } = await query;
  if (error) {
    throw new Error(`${callerLabel}: ${normalizeSupabaseError(error).message}`);
  }
  return data ?? [];
}
