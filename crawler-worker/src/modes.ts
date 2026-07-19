// Worker execution modes. Extracted from index.ts so mode parsing is unit-
// testable without importing index.ts (which runs main() on import).
//
// Crawl modes are UNCHANGED:
//   dry-run   validate config + connectivity + worker RPC availability; no mutation
//   one-shot  claim + process ONE crawl job (test jobs only unless dev flag), then exit
//   poll      production-shaped crawl loop; REFUSES unless CRAWLER_ALLOW_NON_TEST_JOBS
// Additive (P1a Step 3):
//   verify-once  claim + resolve ONE DNS-TXT ownership-verification item, then exit.
//                Fully independent of the crawl processor / crawl-job lifecycle.
import { ConfigError } from "./config.js";

export type Mode = "dry-run" | "one-shot" | "poll" | "verify-once";

const MODES: Mode[] = ["dry-run", "one-shot", "poll", "verify-once"];

export function parseMode(argv: string[]): Mode {
  const arg = argv.find((a) => a.startsWith("--mode="));
  const mode = (arg?.split("=")[1] ?? "dry-run") as Mode;
  if (!MODES.includes(mode)) {
    throw new ConfigError(`unknown --mode "${mode}" (expected ${MODES.join("|")})`);
  }
  return mode;
}
