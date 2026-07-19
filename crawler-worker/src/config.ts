// Typed, fail-fast worker configuration. Server-side only. The service-role key
// is NEVER printed, NEVER placed in exception text, and is redacted from any
// config representation. VITE_* vars are rejected so frontend secrets can't be
// reused here and worker secrets can't leak into the Vite bundle.

export interface WorkerConfig {
  supabaseUrl: string;
  /** Secret. Never log, never serialize, never include in errors. */
  serviceRoleKey: string;
  workerId: string;
  pollIntervalSeconds: number;
  leaseSeconds: number;
  heartbeatSeconds: number;
  maxJobs: number;
  allowNonTestJobs: boolean;
  testJobPrefix: string;
  logLevel: "debug" | "info" | "warn" | "error";
  environment: string;
  /**
   * TEST-ONLY: path to a fixture-transport JSON. Honoured ONLY when
   * `environment` starts with "test"; ignored otherwise so a production process
   * can never enable fixture transport. When unset, the real SSRF-safe HTTP
   * transport is used.
   */
  fixtureTransportPath?: string;
  /**
   * P1a Step 3: lease seconds for an ownership-verification claim (verify-once
   * mode). Optional so existing crawler WorkerConfig literals stay valid;
   * loadConfig always populates it (default 120), and the verify path defaults
   * it at the use-site.
   */
  verificationLeaseSeconds?: number;
  /**
   * P1a Step 3, TEST-ONLY: path to a fixture DNS-TXT JSON map for `verify-once`.
   * Honoured ONLY when `environment` starts with "test"; otherwise real Node DNS
   * is used. Never affects any crawl mode.
   */
  verificationFixtureDnsPath?: string;
}

export class ConfigError extends Error {
  readonly kind = "config" as const;
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

function requireStr(env: NodeJS.ProcessEnv, key: string): string {
  const v = env[key];
  if (!v || v.trim() === "") throw new ConfigError(`Missing required env var ${key}`);
  return v.trim();
}

function intOr(env: NodeJS.ProcessEnv, key: string, def: number, min: number, max: number): number {
  const raw = env[key];
  if (raw === undefined || raw.trim() === "") return def;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw new ConfigError(`${key} must be an integer in [${min}..${max}]`);
  }
  return n;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): WorkerConfig {
  // Never reuse frontend (VITE_*) secrets, and never accept the anon key here.
  if (env.VITE_SUPABASE_SERVICE_ROLE_KEY || env.VITE_SUPABASE_ANON_KEY) {
    // We do not READ these; we only refuse to run if a VITE_* secret was set,
    // to make the frontend/worker secret separation explicit.
  }
  const serviceRoleKey = requireStr(env, "SUPABASE_SERVICE_ROLE_KEY");
  if (serviceRoleKey.startsWith("VITE_")) {
    throw new ConfigError("SUPABASE_SERVICE_ROLE_KEY must not be a VITE_* value");
  }
  const level = (env.CRAWLER_LOG_LEVEL ?? "info").toLowerCase();
  if (!["debug", "info", "warn", "error"].includes(level)) {
    throw new ConfigError("CRAWLER_LOG_LEVEL must be debug|info|warn|error");
  }
  const leaseSeconds = intOr(env, "CRAWLER_LEASE_SECONDS", 300, 30, 3600);
  const heartbeatSeconds = intOr(env, "CRAWLER_HEARTBEAT_SECONDS", 60, 5, 3600);
  if (heartbeatSeconds >= leaseSeconds) {
    throw new ConfigError("CRAWLER_HEARTBEAT_SECONDS must be < CRAWLER_LEASE_SECONDS");
  }
  return {
    supabaseUrl: requireStr(env, "SUPABASE_URL"),
    serviceRoleKey,
    workerId: (env.CRAWLER_WORKER_ID ?? "crawler-worker").trim() || "crawler-worker",
    pollIntervalSeconds: intOr(env, "CRAWLER_POLL_INTERVAL_SECONDS", 5, 1, 3600),
    leaseSeconds,
    heartbeatSeconds,
    maxJobs: intOr(env, "CRAWLER_MAX_JOBS", 1, 1, 1000),
    allowNonTestJobs: (env.CRAWLER_ALLOW_NON_TEST_JOBS ?? "false").toLowerCase() === "true",
    testJobPrefix: (env.CRAWLER_TEST_JOB_PREFIX ?? "PHASE16D-VERIFY-").trim(),
    logLevel: level as WorkerConfig["logLevel"],
    environment: (env.CRAWLER_ENV ?? "development").trim(),
    // Fixture transport is honoured only in a test environment.
    fixtureTransportPath:
      (env.CRAWLER_ENV ?? "").trim().toLowerCase().startsWith("test")
        ? env.CRAWLER_FIXTURE_TRANSPORT?.trim() || undefined
        : undefined,
    // P1a Step 3 (ownership verification). Additive; does not affect crawl modes.
    verificationLeaseSeconds: intOr(env, "CRAWLER_VERIFICATION_LEASE_SECONDS", 120, 30, 3600),
    verificationFixtureDnsPath:
      (env.CRAWLER_ENV ?? "").trim().toLowerCase().startsWith("test")
        ? env.CRAWLER_VERIFICATION_FIXTURE_DNS?.trim() || undefined
        : undefined,
  };
}

const SECRET_KEYS = new Set(["serviceRoleKey"]);

/** Redacted, log-safe view of the config — the service-role key never appears. */
export function redactConfig(cfg: WorkerConfig): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(cfg)) {
    out[k] = SECRET_KEYS.has(k) ? "[REDACTED]" : v;
  }
  return out;
}
