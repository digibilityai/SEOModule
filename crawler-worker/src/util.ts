export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Deterministic bounded exponential backoff. attemptNumber is 1-based.
 * delay = min(maxSeconds, baseSeconds * 2^(attemptNumber-1)). No jitter, so it
 * is unit-testable; returns an ISO timestamp for `retry_after`.
 */
export function computeRetryAfter(
  attemptNumber: number,
  baseSeconds = 30,
  maxSeconds = 3600,
  now: Date = new Date(),
): string {
  const exp = Math.max(0, attemptNumber - 1);
  const delay = Math.min(maxSeconds, baseSeconds * 2 ** exp);
  return new Date(now.getTime() + delay * 1000).toISOString();
}
