// Structured JSON logging suitable for local dev + future Cloud Run. Never logs
// secrets, tokens, authorization headers, raw sessions, passwords, whole env
// maps, or page content. A small redactor scrubs known-sensitive keys and any
// value that looks like a JWT/service key from log fields defensively.

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 } as const;
export type LogLevel = keyof typeof LEVELS;

const SENSITIVE_KEY = /(service_role|serviceRoleKey|secret|password|token|authorization|apikey|api_key|anon_key)/i;
const JWT_LIKE = /^ey[A-Za-z0-9_-]{10,}\./; // JWT / Supabase key shape

function redactValue(key: string, value: unknown): unknown {
  if (SENSITIVE_KEY.test(key)) return "[REDACTED]";
  if (typeof value === "string" && JWT_LIKE.test(value)) return "[REDACTED]";
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) out[k] = redactValue(k, v);
    return out;
  }
  return value;
}

export interface LogFields {
  jobId?: string;
  attemptNumber?: number;
  correlationId?: string;
  action?: string;
  outcome?: string;
  durationMs?: number;
  [k: string]: unknown;
}

export class Logger {
  constructor(
    private readonly minLevel: LogLevel,
    private readonly base: { workerId: string; environment: string },
  ) {}

  private emit(level: LogLevel, msg: string, fields: LogFields = {}): void {
    if (LEVELS[level] < LEVELS[this.minLevel]) return;
    const safe: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(fields)) safe[k] = redactValue(k, v);
    const line = {
      ts: new Date().toISOString(),
      level,
      env: this.base.environment,
      workerId: this.base.workerId,
      msg,
      ...safe,
    };
    const out = JSON.stringify(line);
    if (level === "error" || level === "warn") process.stderr.write(out + "\n");
    else process.stdout.write(out + "\n");
  }

  debug(msg: string, f?: LogFields) { this.emit("debug", msg, f); }
  info(msg: string, f?: LogFields) { this.emit("info", msg, f); }
  warn(msg: string, f?: LogFields) { this.emit("warn", msg, f); }
  error(msg: string, f?: LogFields) { this.emit("error", msg, f); }

  child(fields: LogFields): BoundLogger { return new BoundLogger(this, fields); }
}

/** A logger bound to a job's correlation context. */
export class BoundLogger {
  constructor(private readonly parent: Logger, private readonly bound: LogFields) {}
  private merge(f?: LogFields): LogFields { return { ...this.bound, ...f }; }
  debug(msg: string, f?: LogFields) { this.parent.debug(msg, this.merge(f)); }
  info(msg: string, f?: LogFields) { this.parent.info(msg, this.merge(f)); }
  warn(msg: string, f?: LogFields) { this.parent.warn(msg, this.merge(f)); }
  error(msg: string, f?: LogFields) { this.parent.error(msg, this.merge(f)); }
}

// Exported for unit testing the redactor.
export const _redactForTest = redactValue;
