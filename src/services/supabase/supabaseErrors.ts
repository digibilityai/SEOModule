export interface NormalizedSupabaseError {
  message: string;
  code?: string;
  raw: unknown;
}

/**
 * Supabase/PostgREST errors, thrown JS Errors, and unknown thrown values all
 * arrive in different shapes. This normalizes them into one predictable
 * shape so services/UI can show a clear, dev-facing message instead of
 * "[object Object]" or an unhandled crash.
 */
export function normalizeSupabaseError(error: unknown): NormalizedSupabaseError {
  if (error && typeof error === "object") {
    const maybe = error as {
      message?: unknown;
      code?: unknown;
      error_description?: unknown;
    };
    const message =
      (typeof maybe.message === "string" && maybe.message) ||
      (typeof maybe.error_description === "string" && maybe.error_description) ||
      "Unknown Supabase error";
    const code = typeof maybe.code === "string" ? maybe.code : undefined;
    return { message, code, raw: error };
  }

  if (typeof error === "string") {
    return { message: error, raw: error };
  }

  return { message: "Unknown Supabase error", raw: error };
}

export function normalizeSupabaseErrorMessage(error: unknown): string {
  return normalizeSupabaseError(error).message;
}
