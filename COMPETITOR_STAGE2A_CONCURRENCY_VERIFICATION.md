# Competitor Benchmarking Stage 2A — Concurrency (advisory lock) Two-Session Verification

**TEST ONLY — `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`). Do NOT run on production.**
No secrets or service-role credentials are used (jwt claims set the seeded owner's
`sub`; the RPC runs under the `authenticated` role).

This guide proves the transaction-scoped `pg_advisory_xact_lock` serialization of
`public.seo_competitor_generate(p_website_id uuid)` (Competitor Stage 2A, migration
`20260724120040_seo_competitor_generate.sql`). The self-contained SQL verification
(`supabase/test/seo_competitor_generate_verification.sql`) proves this **statically**
(the lock call is present in the deployed function body) but cannot execute a true
two-session race in one transaction. This guide follows the same method already
proven for P1b (`P1B_CONCURRENCY_VERIFICATION_GUIDE.md`): two concurrent
`supabase db query --linked -f <file>` invocations, each holding **one transaction
per file** for its full duration (confirmed by the P1b guide via
`txid_current() = txid_current()`, and re-confirmed here — see "Method" below).

---

## Method

- **Session A** (`session_a.sql`): sets the seeded owner's jwt claim, calls
  `seo_competitor_generate` (which internally acquires
  `pg_advisory_xact_lock(hashtextextended(website_id || ':competitor_generate', 0))`
  and performs the replace-to-match upsert), then **`SELECT pg_sleep(8)`** — holding
  the transaction (and therefore the still-held advisory lock, which is
  transaction-scoped and only released at COMMIT) open for 8 seconds before the file
  ends and the transaction implicitly commits.
- **Session B** (`session_b.sql`): started **~1.5 s after** Session A, sets the same
  jwt claim, and calls `seo_competitor_generate` on the **same website** — its
  internal `pg_advisory_xact_lock` call is expected to **block** until Session A's
  transaction commits.
- **Observer** (`poll.sql`): a third, brief `supabase db query --linked` invocation
  run twice during the race window, querying `pg_stat_activity` for both sessions'
  `wait_event_type`/`wait_event`.
- Fixture: disposable workspace `c2cc0000-0000-0000-0001-000000000001` / website
  `c2cc0000-0000-0000-0002-000000000002`, owned by the shared TEST seed user
  (`48c479db-aedf-452e-af43-05ed1180baaa`), with onboarding competitors
  `['https://alpha-conc.example', 'https://beta-conc.example']`.

---

## Executed on TEST — RESULTS (2026-07-24, `Digi_SEO_Test`)

**Timeline (bash-side, `date +%s.%N` around each launch):**

| Event | Epoch (s) | Offset from A-start |
|---|---|---|
| Session A launched | `1784867889.527447` | 0.000 s |
| Session B launched | `1784867891.046646` | +1.519 s |
| Poll #1 executed | `1784867893.561847` | +4.038 s |
| Poll #2 executed | `1784867898.047718` | +8.524 s |
| Session A finished (bash `wait`) | `1784867899.459944` | +9.936 s |
| Session B finished (bash `wait`) | `1784867899.462261` | +9.939 s |

**Poll #1 — direct observation of the waiting session (`pg_stat_activity`):**

```
 pid     | state  | wait_event_type | wait_event | elapsed
---------+--------+------------------+------------+----------------
 1526454 | active | Timeout          | PgSleep    | 00:00:04.006509   <- Session A, mid pg_sleep(8), holding the lock
 1526458 | active | Lock             | advisory   | 00:00:02.286385   <- Session B, BLOCKED on the advisory lock
```

Session B had already been waiting on the `advisory` lock for **~2.29 s** at the
moment of Poll #1 — direct, unambiguous proof that the second concurrent call to
`seo_competitor_generate` blocks on the same advisory-lock key while the first
call's transaction is still open.

**Poll #2** (t ≈ +8.52 s): zero matching rows — both sessions had already completed
and their connections closed (Session A's `pg_sleep(8)` had elapsed and its
transaction committed; Session B unblocked immediately after and finished quickly).

**Commit → resume:** Session A's transaction (INSERT of both competitor rows,
`ON CONFLICT` not yet triggered) committed after its 8-second sleep. Session B then
immediately unblocked, re-evaluated the now-committed rows, and completed its own
`ON CONFLICT DO UPDATE` pass — confirmed by the post-race row state:

```
 normalized_competitor_url | overall_strength_score | data_provenance | generation_method | created_at              | updated_at
----------------------------+-------------------------+------------------+--------------------+-------------------------+-------------------------
 alpha-conc.example         | 68                      | estimated        | heuristic_v1        | 2026-07-24 04:38:10.603 | 2026-07-24 04:38:12.323
 beta-conc.example          | 54                      | estimated        | heuristic_v1        | 2026-07-24 04:38:10.603 | 2026-07-24 04:38:12.323
```

- **Exactly one canonical competitor set exists:** `count(*) = 2`,
  `count(DISTINCT normalized_competitor_url) = 2` — no duplicates, no
  unique-constraint error from either session.
- **`created_at` identical on both rows** — both were inserted by Session A's single
  transaction (the INSERT, not the UPDATE, path of `ON CONFLICT`).
- **`updated_at` identical on both rows, later than `created_at`** — both were then
  refreshed by Session B's `ON CONFLICT DO UPDATE` pass once it unblocked, confirming
  B ran the UPDATE branch (not a second INSERT) against the already-committed rows —
  i.e., no race condition, no duplicate-key error, no partial/interleaved write.
- **Only `estimated` provenance / `heuristic_v1` generation_method** persisted on
  both rows, consistent with the RPC contract under concurrent load.

**Replace-to-match re-verified after the race:** onboarding was updated to swap
`beta-conc.example` → `gamma-conc.example`; a subsequent single-session call to
`seo_competitor_generate` returned `2` and left the set as
`{alpha-conc.example, gamma-conc.example}` — `beta-conc.example` correctly removed,
`alpha-conc.example` preserved, `gamma-conc.example` added. Replace-to-match behaves
identically after the concurrent race as it does in isolation.

**Teardown / residue:** all 5 disposable fixture tables (`seo_competitors`,
`seo_business_onboarding`, `seo_websites`, `seo_workspace_members`,
`seo_workspaces`) checked by id-prefix after teardown — **all 0**. No residue.

---

## Interpretation

- The advisory lock **is** enforced at the database/transaction level, exactly as
  intended: a second concurrent call to `seo_competitor_generate` for the same
  website **blocks** (observed directly via `pg_stat_activity`/`pg_locks`
  `wait_event_type=Lock, wait_event=advisory`) until the first call's transaction
  commits.
- Because the target table also carries `UNIQUE(website_id,
  normalized_competitor_url)` (Stage 1) and the RPC uses
  `INSERT … ON CONFLICT DO UPDATE`, the **combination** of the advisory lock
  (serializing concurrent generations so they don't interleave writes) and the
  unique key (the final backstop) converges to exactly one canonical row per
  competitor with no duplicates and no errors — proven by direct row inspection
  after the race, not just by the lock-wait observation alone.
- Replace-to-match, provenance (`estimated`), and generation method
  (`heuristic_v1`) are unaffected by concurrent execution.
- No deadlock is possible: a single advisory-lock key per (website, operation) with
  no other lock acquired inside the same critical section.

---

## Reproduction

Scripts used (disposable, not checked into the repo — recreate from this guide if
re-running):

```sql
-- session_a.sql
SELECT set_config('request.jwt.claims', json_build_object('sub','<seed-owner-uuid>','role','authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT public.seo_competitor_generate('<website_id>'::uuid) AS a_result;
SELECT pg_sleep(8);

-- session_b.sql (launched ~1.5s after session_a.sql)
SELECT set_config('request.jwt.claims', json_build_object('sub','<seed-owner-uuid>','role','authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT public.seo_competitor_generate('<website_id>'::uuid) AS b_result;

-- poll.sql (run 1-2x during the 8s window from a third invocation)
SELECT pid, state, wait_event_type, wait_event, now()-query_start AS elapsed, left(query,60) AS query
FROM pg_stat_activity
WHERE query ILIKE '%seo_competitor_generate%' AND pid <> pg_backend_pid()
ORDER BY query_start;
```

Run via `supabase db query --linked -f session_a.sql &`, stagger ~1.5 s, then
`supabase db query --linked -f session_b.sql &`, poll during the window, `wait` for
both, then inspect + tear down.
