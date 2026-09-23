// D-026A Stage 2 hardening. The `launchCode` is a one-time credential that the
// brain-connect page only needs for the flow it is already running. Once the
// page has captured it in component memory, leaving it in the address bar makes
// it copyable, shareable and re-readable from browser history for no benefit.
//
// This module does one thing: rewrite the visible URL so the code is gone. It
// is a history rewrite only — `replaceState` never navigates or reloads, and
// the code is never written to localStorage or sessionStorage.
const LAUNCH_CODE_PARAM = "launchCode";

/**
 * The narrow slice of `window` this rewrite needs. Declared structurally so the
 * behaviour is testable in the repo's node test environment without a DOM.
 */
export interface LaunchCodeUrlTarget {
  location: { href: string };
  history: {
    state: unknown;
    replaceState: (state: unknown, unused: string, url: string) => void;
  };
}

/**
 * Removes `launchCode` from the visible URL of `target`, preserving the path,
 * every other query parameter and the hash. No-op when there is no usable
 * History API, when the href cannot be parsed, or when there is no
 * `launchCode` left to remove (so repeat calls are safe).
 */
export function stripLaunchCodeFromUrl(target: LaunchCodeUrlTarget | undefined): void {
  if (typeof target?.history?.replaceState !== "function") return;

  let url: URL;
  try {
    url = new URL(target.location.href);
  } catch {
    return;
  }

  if (!url.searchParams.has(LAUNCH_CODE_PARAM)) return;
  url.searchParams.delete(LAUNCH_CODE_PARAM);

  target.history.replaceState(target.history.state, "", `${url.pathname}${url.search}${url.hash}`);
}
