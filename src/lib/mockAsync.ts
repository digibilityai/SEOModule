// Wraps synchronous mock reads in a Promise so services already look like
// the async Supabase calls they'll become in Phase 12.
export function toAsync<T>(value: T): Promise<T> {
  return Promise.resolve(value);
}
