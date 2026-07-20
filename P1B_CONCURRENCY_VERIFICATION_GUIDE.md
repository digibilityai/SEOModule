# P1b — Concurrency (FOR SHARE) Two-Session Verification Guide

**TEST ONLY — `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`). Do NOT run on production.**
No secrets or real-domain challenge values are used.

This guide proves the `FOR SHARE` write-time atomicity of the P1b verified-only
enqueue guard in `public.seo_crawl_request`. The single-transaction
`supabase db query --linked -f` runner cannot execute a true two-session race, so
this is a **runnable manual procedure** using two concurrent psql sessions
(Session A / Session B). The automated verification script
`supabase/test/seo_p1b_verified_only_crawl_enqueue_verification.sql` separately
proves (statically) that the `FOR SHARE` lock and the guard are present in the
deployed function — this guide proves the runtime blocking/rejection behaviour.

**Prerequisite:** the P1b migration `20260719120034_seo_p1b_verified_only_crawl_enqueue.sql`
is applied, and two psql sessions are open against `Digi_SEO_Test` connected as a
role that can call the RPC as the seeded owner (or run as `postgres` and set the
jwt claims shown below). Both sessions target the same TEST database.

---

## Setup (run once, either session, as postgres)

```sql
-- Disposable VERIFIED site in the seed workspace owned by the seed owner.
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES ('b1b00000-0000-0000-0002-0000000000c1', '44444444-0000-0000-0001-000000000001',
        'https://p1b-race.example', 'P1B Race', 'P1B', 'other','pending',true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.seo_ownership_verifications
  (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, verified_at)
VALUES ('44444444-0000-0000-0001-000000000001', 'b1b00000-0000-0000-0002-0000000000c1',
        'https://p1b-race.example', 'p1b-race.example', 'dns_txt', 'verified', 'P1B-RACE-TOKEN', now())
ON CONFLICT (website_id, method) DO UPDATE
  SET status='verified', challenge_token='P1B-RACE-TOKEN', verified_at=now(), updated_at=now();
```

In each session that calls the RPC, set the seeded owner identity first:

```sql
SELECT set_config('request.jwt.claim.sub', '48c479db-aedf-452e-af43-05ed1180baaa', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub','48c479db-aedf-452e-af43-05ed1180baaa','role','authenticated')::text, true);
```

---

## Scenario 1 — Enqueue wins (revoke serializes AFTER)

Proves: if the enqueue takes the `FOR SHARE` lock first, a concurrent revoke
**blocks** until the enqueue commits; the enqueue succeeds against the verified
state.

**Session A**
```sql
BEGIN;
-- (set jwt claims as above)
SELECT public.seo_crawl_request('b1b00000-0000-0000-0002-0000000000c1', 'A-wins', NULL);
-- returns a job uuid; FOR SHARE lock on the ownership row is now held. Leave open.
```

**Session B** (while A is open)
```sql
BEGIN;
UPDATE public.seo_ownership_verifications
   SET status='revoked', updated_at=now()
 WHERE website_id='b1b00000-0000-0000-0002-0000000000c1' AND method='dns_txt';
-- EXPECTED: this statement BLOCKS (waits on A's FOR SHARE lock).
```

**Session A**
```sql
COMMIT;   -- job committed while ownership was verified
```

**Session B** (now unblocks)
```sql
-- The UPDATE completes; revoke applies AFTER the enqueue.
COMMIT;
```

**Expected outcome:** A's job is created (verified at commit time); B's revoke
blocked until A committed, then applied. Correct serialization.

**Reset for Scenario 2:**
```sql
DELETE FROM public.seo_crawl_jobs WHERE website_id='b1b00000-0000-0000-0002-0000000000c1';
UPDATE public.seo_ownership_verifications SET status='verified', verified_at=now(), updated_at=now()
 WHERE website_id='b1b00000-0000-0000-0002-0000000000c1' AND method='dns_txt';
```

---

## Scenario 2 — Revoke wins (enqueue REJECTED at write time)

Proves: if the revoke takes the lock first, the enqueue **blocks**, then after the
revoke commits it **re-evaluates** the row (EvalPlanQual), finds status ≠ `verified`,
and is **rejected**. This is the write-time correctness the plan requires.

**Session B**
```sql
BEGIN;
UPDATE public.seo_ownership_verifications
   SET status='revoked', updated_at=now()
 WHERE website_id='b1b00000-0000-0000-0002-0000000000c1' AND method='dns_txt';
-- row now locked FOR NO KEY UPDATE (uncommitted). Leave open.
```

**Session A** (while B is open)
```sql
BEGIN;
-- (set jwt claims as above)
SELECT public.seo_crawl_request('b1b00000-0000-0000-0002-0000000000c1', 'B-wins', NULL);
-- EXPECTED: this statement BLOCKS on B's row lock (the FOR SHARE inside the guard).
```

**Session B**
```sql
COMMIT;   -- revoke committed → status='revoked'
```

**Session A** (now unblocks)
```
-- EXPECTED: ERROR:  Domain ownership must be verified before this website can be crawled.
-- The FOR SHARE re-checked the updated row, which no longer matches status='verified'.
```
```sql
ROLLBACK;  -- (A already errored; no job was created)
```

**Expected outcome:** A blocked until B committed, then A was **rejected** with the
P1b ownership message; **no crawl job was created**. Blocked at write time.

**Verify no job leaked:**
```sql
SELECT count(*) AS jobs FROM public.seo_crawl_jobs
 WHERE website_id='b1b00000-0000-0000-0002-0000000000c1';   -- expect 0
```

---

## Teardown (run once, as postgres)

```sql
DELETE FROM public.seo_crawl_jobs WHERE website_id='b1b00000-0000-0000-0002-0000000000c1';
DELETE FROM public.seo_ownership_verifications WHERE challenge_token='P1B-RACE-TOKEN';
DELETE FROM public.seo_websites WHERE id='b1b00000-0000-0000-0002-0000000000c1';
```

---

## Interpretation

- **Both scenarios show blocking** — the `FOR SHARE` lock and the revoke's
  `FOR NO KEY UPDATE` lock conflict and serialize on the single ownership row.
- **Scenario 2 shows rejection at write time** — the key correctness property:
  a revoke that commits during the enqueue attempt causes the enqueue to be
  rejected, not to create a job against a now-revoked website.
- `FOR KEY SHARE` would **not** produce this blocking (it does not conflict with a
  non-key `status` UPDATE), which is why `FOR SHARE` is required — do not weaken it.
- No deadlock is possible: the only shared lock target is the single ownership row.

---

## Executed on TEST — RESULTS (2026-07-19, `Digi_SEO_Test`)

Both scenarios were run with two concurrent `supabase db query --linked` sessions
(the runner holds one transaction across a file, verified via
`txid_current() = txid_current()` → true, so `FOR SHARE` locks persist while a
session sleeps). Fixture site `b1b00000-0000-0000-0002-0000000000c1` (disposable,
seed workspace, verified). Seed owner identity via jwt claims. No secrets printed.

- **Scenario B — revoke wins → PASS.** Session B took the revoke lock and held its
  transaction ~6 s; Session A's enqueue (started ~1.5 s later) **blocked ~6.3 s**,
  then **failed with SQLSTATE `P0001`**: `Domain ownership must be verified before
  this website can be crawled.` (raised inside `seo_crawl_request`). Post-check:
  **0 crawl jobs** for the site; ownership = `revoked`. Blocked-and-rejected at
  write time, exactly as designed.
- **Scenario A — enqueue wins → PASS.** Session A's enqueue took the `FOR SHARE`
  lock and held ~6 s; Session B's revoke (started ~1.5 s later) **blocked ~6.1 s**
  until A committed, then applied. Post-check: **1 crawl job** created (while
  verified); ownership = `revoked` afterward. Correct serialization.
- **Teardown:** race fixture removed; 0 residual (race site, P1b ownership rows,
  P1b verify sites, orphan audit runs all 0).

Conclusion: the `FOR SHARE` write-time atomicity is proven at runtime on TEST.
