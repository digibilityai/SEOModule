// Transport abstraction. ALL Phase 1C network access goes through a Transport
// (the real SafeHttpTransport, or a TEST-only FixtureTransport). No discovery
// module ever touches a generic HTTP client directly. Injecting the transport
// makes the security + discovery logic fully unit-testable without live network.

export type FetchPurpose = "robots" | "sitemap" | "html";

export interface FetchOptions {
  purpose: FetchPurpose;
  maxBytes: number;
  timeoutMs: number;
  maxRedirects: number;
  allowedMimeTypes: string[];
  signal?: AbortSignal;
}

export type DecodeStatus = "ok" | "unsupported";

export interface FetchResult {
  finalUrl: string;
  status: number;
  contentType: string;
  bodyText: string; // bounded, decoded; possibly truncated. Never logged/persisted.
  bytes: number;
  redirectCount: number;
  truncated: boolean;
  durationMs: number;
  /** Charset label used for decoding (from header/meta), or undefined for the utf-8 default. */
  declaredCharset?: string;
  /** "unsupported" = a declared charset label was unknown; decoded as utf-8 fallback. */
  decodeStatus: DecodeStatus;
  /** Allowlisted response header only (indexing directive); never other headers. */
  xRobotsTag?: string;
}

export class FetchError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly retryable: boolean = false,
  ) {
    super(message);
    this.name = "FetchError";
  }
}

export interface Transport {
  fetch(url: string, opts: FetchOptions): Promise<FetchResult>;
}
