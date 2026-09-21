# SEO Module: Digi Brain Module Contract v1 interface (Stage 2B)

**Status:** implemented on branch `feat/seo-brain-module-contract-stage2b`.
**All four Stage 2B migrations remain UNAPPLIED. Nothing has been applied to any
Supabase project, TEST integration is still pending, and nothing has been
deployed.**

This document describes the SEO side of the machine boundary. The contract
itself is owned by Digi Brain and is frozen at commit `0159a3f`
(`feat(modular-arch): Stage 1, generic Module Contract v1`, PR #147),
`server/modules/types.ts`. SEO does not extend it.

## 1. What is exposed

Six capabilities. The keys are **Digi Brain's**, taken verbatim from its frozen
Stage 2A adapter (`Digi_Brain` `96baf21`, `server/modules/seo/capabilities.ts`).

| Capability key | Family | Answers | Genuine source | Provenance |
|---|---|---|---|---|
| `analyse.target_linkage` | analyse | Is this Business linked to exactly one SEO website for this host | `seo_brain_website_links` | `customer_provided` / `declared` |
| `analyse.ownership_verification` | analyse | Is domain ownership verified | `seo_ownership_verifications` (real DNS TXT) | `measured_external` / `measured` once a check has run, `calculated` / `derived` when none has |
| `execute.technical_audit` | execute | Start a genuine crawl and audit | `seo_crawl_request_audit` plus the crawler worker | `calculated` / `derived` |
| `analyse.technical_audit` | analyse | What did the crawler find | `seo_audit_issues` where `source='crawler'`, latest completed run | `measured_external` / `measured` once a crawl has completed, `calculated` / `derived` when none has |
| `execute.recommendations` | execute | Generate rule-based recommendations | `seo_recommendation_generate` | `calculated` / `derived`, `generationMethod` from the stored rows |
| `analyse.recommendations` | analyse | Current recommendation set | `seo_recommendations` where `is_current` and `generation_method` is not null | `calculated` / `derived` |

A STATUS poll reuses the originating `execute.*` key. There is no `status.*`
namespace.

Every response is `dataAuthenticity: "genuine"`. An execute that declines to
start work returns a genuine acknowledgement with `accepted: false` and SEO's
own `moduleStatus`, rather than an opaque error, so Brain can tell a blocked
precondition apart from a failure. Brain must inspect that flag; see the
integration requirement in section 7.

**An empty result never claims a measurement.** Two capabilities have a
legitimate "nothing has happened yet" state, and both report it as
`calculated` / `derived` rather than as an observation that did not occur:
ownership verification before any DNS check has run, and the technical audit
before any crawl has completed. A completed crawl that genuinely found nothing
is still `measured_external` / `measured`, because a real outbound observation
did take place. The distinction is the difference between "we looked and found
nothing" and "we have not looked".

### Capability key reconciliation

The first Stage 2B commit used working names for four of the six. Brain's names
are now used, because Brain refuses any key its own adapter does not list and
this module refuses any key it does not declare, so a mismatch is a total
integration failure rather than a cosmetic difference. Contract v1 leaves the
operation half of a key to the module, so this is not a contract change.

| First Stage 2B commit | Now (Brain Stage 2A) |
|---|---|
| `analyse.target_linkage` | unchanged |
| `analyse.ownership_verification` | unchanged |
| `execute.technical_crawl` (withheld) | `execute.technical_audit` |
| `analyse.crawl_findings` | `analyse.technical_audit` |
| `analyse.recommendation_generation` (withheld) | `execute.recommendations` |
| `analyse.current_recommendations` | `analyse.recommendations` |

Recommendation generation also moved family: Brain models it as EXECUTE with a
`brainActionId` and an `idempotencyKey`, followed by a separate ANALYSE read.

Deliberately **not** exposed, and refused with `unsupported_capability`:
`seo_run_audit` (a stub that creates a run row and no findings), competitor
benchmarking (hash derived estimates), Page Performance (`manual_seed` only, no
GSC or GA4 integration exists), Decline Diagnosis (storage with no engine), AI
Visibility (manual and import only), Roadmap (no backend at all), Content Studio
publishing, off page execution, manual completion, expert routing, and mixed
provenance reports.

## 2. Actor mapping

Digi Brain's `actorId` identifies a human in the Brain Supabase project. SEO
users are rows in the SEO project's own `auth.users`. The mapping is one new
table, `seo_brain_actor_links`, holding a Brain actor identifier, an SEO
`auth.users` id, a status and who authorized it. Nothing else: no email, no
name, no role. Those already live in `auth.users`, `seo_workspace_members` and
`seo_identity_profiles`, and a second copy would drift.

**It establishes identity only and grants no permission.** After an actor
resolves, every delegated capability runs the existing chain unchanged:

```
Brain actorId
  -> seo_brain_actor_links (active)      identity
  -> has_seo_module_access               existing gate
  -> seo_role_in(workspace, owner|admin|team_member)   existing role matrix
  -> the target website's own workspace
```

A mapped user with no workspace membership resolves successfully and is then
refused. That is asserted in both the TypeScript tests and the SQL verification.

**Never used to infer identity:** email matching, display names, workspace
ownership, most recent membership, `seo_brain_website_links.linked_by`, SSO
session assumptions, or the machine credential. The machine credential
authenticates the transport only.

**Creation is a human action.** Only a global admin may insert a mapping, which
is deliberately narrower than the owner/admin rule used for website links: an
actor link is a platform level identity assertion, and letting any workspace
admin bind an arbitrary Brain actor to an arbitrary SEO user would be an
impersonation vector. A person may revoke their own mapping; a global admin may
revoke any. There is no machine path to creation, and no mapping is ever derived
from an existing SSO record.

**Revocation fails closed** and is terminal. A revoked mapping stops resolving
immediately and cannot be reactivated; a new row is required. The Brain actor
and the SEO user on an existing row are both immutable.

### Creating the first mapping: the operator bootstrap

> **Corrected 2026-09-20 (migration `20260920120400`).** An earlier version of
> this section said `public.seo_is_global_admin()` "effectively only depends on
> `public.profiles`", which this repository never creates. **That rationale was
> wrong** and the live `Digi_SEO_Test` state disproved it: migration
> `20260720121000_seo_cross_project_identity_bridge` extends
> `seo_is_global_admin()` through `public.seo_identity_profiles`, so
> `public.profiles` is not its only source. The corrected reason is below. The
> global-admin architecture itself is unchanged and is deliberately not
> redesigned here.

The bootstrap exists because **a target environment may contain no currently
reachable global-admin identity at all.** Which table `seo_is_global_admin()`
resolves an admin from is beside the point; what matters is that on
`Digi_SEO_Test` no signed-in session satisfies it today, so **no authenticated
session can satisfy the INSERT policy and there is no reachable global admin to
authorize the first mapping.** Without a way in, the delegated write path cannot
be exercised at all.

Two consequences follow, and both are deliberate:

* **Operator bootstrap requires an explicit human authorizer.** With no
  reachable admin session there is no `auth.uid()` to read, so the authorizing
  human is stated by the operator or the insert is refused.
* **No identity is inferred, ever.** Not from an email, not from workspace
  ownership, not from "the only admin", not from the session.

`public.seo_brain_bootstrap_actor_link(p_brain_actor_id, p_seo_user_id,
p_authorized_by)` is that way in, and nothing more. It is not an admin UI, not a
product feature and not a new global-admin system.

* **Granted to nobody.** EXECUTE is revoked from `PUBLIC`, `anon`,
  `authenticated` and `service_role`. Only the database owner, in a direct
  operator session, can call it. The machine endpoint authenticates as
  `service_role` and therefore still has no path of any kind to creating an
  actor mapping. The verification script asserts exactly this before using it.
* **It refuses an authenticated session.** A session carrying a JWT is told to
  use the ordinary RLS path, so the procedure can never become a way around the
  global-admin policy.
* **It identifies the SEO user being linked** as a required `auth.users` id that
  must already exist. Nothing is matched on email, display name, workspace
  ownership, "the only admin", the session, or the linked user.
* **It records who authorized the mapping**, also as a required `auth.users` id
  that must already exist.

**The honest limitation.** A direct SQL session has no `auth.uid()`, and this
schema holds no product-level global-admin record that could truthfully name an
authorizer. The authorizer can therefore only be recorded if the operator states
it, which is why `p_authorized_by` is a required argument with no default. The
guard trigger backs this up: with no session identity it refuses any insert that
names no `linked_by`, and any revoke that names no `revoked_by`, rather than
writing an unattributed NULL. A product-level admin surface would replace this
procedure; that is deliberately out of scope.

**Operator procedure**, run once per person on a project where the Stage 2B
migrations are applied, in a direct SQL session as the database owner:

```sql
-- 1. Confirm both people exist and read their ids. Never guess an id.
SELECT id, email FROM auth.users WHERE email IN ('<person-being-linked>', '<person-authorizing>');

-- 2. Create the mapping, stating both ids explicitly.
SELECT public.seo_brain_bootstrap_actor_link(
  '<the Digi Brain actorId>',
  '<seo auth.users id being linked>'::uuid,
  '<seo auth.users id of the human authorizing this>'::uuid);

-- 3. Confirm what was recorded.
SELECT brain_actor_id, seo_user_id, linked_by, linked_at, link_status
FROM public.seo_brain_actor_links WHERE brain_actor_id = '<the Digi Brain actorId>';

-- To revoke later, name the revoking human in the same statement.
UPDATE public.seo_brain_actor_links
   SET link_status = 'revoked',
       revoked_by  = '<seo auth.users id of the human revoking this>'::uuid,
       revoke_reason = '<why>'
 WHERE brain_actor_id = '<the Digi Brain actorId>' AND link_status = 'active';
```

A mapping still grants nothing. The person linked must separately hold SEO
module access and an `owner`, `admin` or `team_member` role in the target
website's workspace, or every delegated write is refused.

### How a delegated write actually runs

The wrapper resolves the target and the actor, applies the role matrix itself as
a first gate, then sets `request.jwt.claims` for the resolved SEO user and calls
the **existing, unmodified** `seo_crawl_request_audit` or
`seo_recommendation_generate`. Those RPCs therefore run their own checks for
real, the verified-ownership requirement and single-active-job rule behave
exactly as they do for a person in the browser, and
`seo_crawl_jobs.requested_by` records the real human. The impersonation is
transaction local and is restored on both the success and the failure path.
`seo_run_audit` is never called.

Those two RPCs are granted to `authenticated` only. Rather than grant
`service_role` execute on them, which would widen a locked module's grant
surface, the four delegated wrappers are `SECURITY DEFINER` so they can invoke
them as their own owner. That is the only reason they are DEFINER; the read
RPCs remain `SECURITY INVOKER`.

### Operation correlation is scoped per website

One operation correlation exists per **Business + website + capability + Brain
action**, which is exactly how every lookup in the write path scopes itself.
`seo_brain_operations_action_uniq` carries all four columns.

The website matters because one Business can have several websites linked, and
Brain derives one `idempotencyKey` per Brain action and capability with no
website in it. Two consequences follow, and both are handled:

* **The correlation row.** Without `website_id` in the key, a second website
  reusing a Brain action id would collide with the first website's row: the
  recommendation insert would fail outright, and the audit insert's upsert would
  update the other website's row while returning this website's job id, leaving
  the stored handle pointing at a job the website-scoped STATUS lookup can never
  match.
* **The crawl job.** `seo_crawl_jobs` idempotency is **workspace** scoped
  (`workspace_id` plus `idempotency_key`), so handing Brain's key straight
  through would give the second website the first website's crawl job. The
  wrapper therefore binds the website into the key it passes to the control
  plane, `<brain key>@<website id>`, and refuses the call as `invalid_request`
  if that composition would exceed the control plane's 200 character limit.
  Brain's own key is still what is stored on the operation row.

Replay of the same Brain action for the **same** website is unchanged: it
resolves to the same operation and the same crawl job, which is what
idempotency is for.

## 3. Deterministic identity

Resolution is exact or absent. There is no fuzzy matching, no Business name
matching, no host inference across workspaces, no most recent workspace, and no
neighbouring website substitution.

```
Brain businessId + canonical normalized host
        -> seo_brain_website_links (active)
        -> exactly one workspace_id + website_id
```

Guarantees, in order of how they are enforced:

1. `normalized_host` and `workspace_id` on a link row are **derived** by a
   trigger from the linked website's own `website_url`. A caller cannot assert
   either, so a link can never claim host A while pointing at a website whose
   URL is host B.
2. Two partial unique indexes: at most one active link per
   `(business_id, normalized_host)`, and at most one active link per
   `website_id`.
3. Creating a link is a human action gated by the existing `owner`/`admin`
   role check. No machine path can create one.
4. Every delegated RPC takes `(p_business_id, p_normalized_host)` and **never**
   a `website_id` or `workspace_id`, so a machine caller cannot name a target.
5. A link stops resolving if the website's URL is later edited to a different
   host, rather than silently following the website to a new identity.
6. Revocation is terminal. A revoked link cannot be reactivated; a new
   authorization is required.

**Canonical host.** `public.seo_brain_normalize_host` mirrors Digi Brain's
`normalizeWebsiteHost`: lowercase the hostname, strip one leading `www.`,
preserve a non default port, keep subdomains distinct, no public suffix
reduction. The two pre-existing SEO normalizers were **not** modified and are
not reused: `seo_ownership_extract_host` keeps `www.` and drops the port, and
the inline normalizer in `seo_competitor_generate` drops the port. Both sit
inside locked modules. A caller that sends a non canonical host is refused with
`invalid_request` rather than silently corrected.

## 4. Transport

One Supabase Edge Function, `supabase/functions/seo-module-api`, in the SEO
project. No new service, no gateway, no queue.

* Server to server only. No CORS allowance, no browser entry point.
* One path per capability family, `/analyse`, `/execute` and `/status`,
  matching Brain's transport exactly. `/verify` and `/result-evidence` are
  refused: SEO declares no capability in either family.
* Authenticated by `Authorization: Bearer <secret>`, which is what Brain sends,
  compared in constant time. The `x-digibility-module-secret` header is also
  accepted for operator tooling and grants nothing extra. A missing or short
  server side secret fails closed with `module_unavailable` rather than serving
  open.
* `GET` on the base path returns the capability declaration, and is
  authenticated too: the set of capabilities SEO exposes is not public.
* `POST` carries one Contract v1 envelope. The HTTP path and the capability
  key must agree, except for a STATUS poll, which arrives on `/status` carrying
  the originating `execute.*` key.
* The service role key is read from the function environment and is never
  logged, echoed or exposed. The browser application still uses the anon key
  and RLS, unchanged.
* Every failure is one normalized `ModuleErrorCode`. The wire body carries only
  the code and a message that reveals nothing about which workspaces, websites
  or links exist. SEO side reasons such as `revoked` or `host_changed` go to the
  log sink only.

Required configuration:

| Variable | Purpose |
|---|---|
| `SUPABASE_URL` | SEO project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | SEO service role, function only |
| `SEO_MODULE_API_SECRET` | shared machine credential, at least 32 characters |

## 5. Mock fallback isolation

The machine path is **structurally** incapable of returning mock data, not
merely careful about it.

* Nothing under `supabase/functions/seo-module-api/` imports from `src/`. The
  browser fallback layer, `src/services/serviceAdapter.ts`,
  `src/services/dataMode.ts` and `src/mocks/`, is therefore not in this
  directory's import graph at all.
* `isolation.test.ts` enforces this mechanically: it scans every non test file
  for an import specifier reaching `src/`, and for any mention of
  `runWithServiceAdapter`, `getSeoDataMode`, `getCurrentSeoWorkspace` or
  `mocks/` in code. Adding one fails the build.
* A database failure returns `module_unavailable`. There is no branch anywhere
  on this path that returns something rather than nothing.
* Two authenticity gates run in SQL, before any TypeScript sees a row:
  `source = 'crawler'` for findings, `generation_method IS NOT NULL` for
  recommendations. The handler re-checks both and raises `not_genuine` if a row
  ever slips through.

## 6. Verification status

| Check | Result |
|---|---|
| `npm test` | **194 passed**, 12 files, of which 146 are the module boundary suites |
| `npx tsc -b` | clean |
| Strict direct check of the non-Deno boundary modules | clean for `contract`, `capabilities`, `handler`, `http`, `port`, `normalize-host`, `supabase-port`. `index.ts` is Deno and is not checkable by project `tsc`; the test files carry a pre-existing union-narrowing pattern. Both are deferred, see section 8. |
| `npm run build` | clean |
| `crawler-worker` suite | **74 passed**, unchanged |
| UUID literal scan of the Stage 2B SQL | 77 literals, **all valid**, parser checked |
| SQL migrations | **NOT executed.** No Postgres, Docker or Supabase local runtime is available in this environment. |

The SQL is **statically reviewed but unverified**. It must be run before anyone
relies on it. Two operator scripts are provided and both now cover the actor
mapping and the delegated writes:

* `supabase/test/seo_brain_module_boundary_verification.sql`, self seeding and
  self cleaning. Covers normalizer parity case for case against
  `normalize-host.test.ts`, trigger derivation, the full resolution matrix,
  revocation, host change, inactive website, both authenticity gates, no
  sibling and no cross tenant substitution, the grant matrix, link RLS, exact
  and revoked actor resolution, the fact that a mapping grants nothing, the
  actor-link bootstrap including its refusals and the fact that no role can
  execute it, the refusal of an unattributed operator insert or revoke, the
  preserved verified-ownership requirement, a real `seo_crawl_jobs` id as the
  operation handle, truthful `requested_by`, idempotent replay, same-key STATUS
  correlation, a foreign operation id failing closed, and one Business's two
  linked websites getting independent operations under the same Brain action.

  **Prerequisites, asserted before the script mutates anything.** It does not
  create Supabase Auth users, in line with every other verification script here:
  `auth.users` rows are created through the Auth API, never from SQL. It opens
  with a fail-fast guard that refuses to run unless the three shared TEST
  fixture users exist and are distinct, the four Stage 2B migrations are
  applied, `seo_brain_bootstrap_actor_link` is present, and no fixtures from a
  previous run are still sitting there. Each refusal names what is missing and
  what to do. The fixture users are the shared TEST identities already used by
  the other guarded-RPC scripts:

  | Setting | id | user |
  |---|---|---|
  | `b1.owner` | `48c479db-aedf-452e-af43-05ed1180baaa` | `seo-owner-test@example.com` |
  | `b1.client` | `6c7a04e0-9985-47c3-aad4-f2f0cc5e092c` | `seo-client-test@example.com` |
  | `b1.nomem` | `0723d21f-c02c-4725-851f-575f93f2f58c` | `seo-team-test@example.com` |
* `supabase/test/seo_brain_module_boundary_rollback_TEST_ONLY.sql`. Drops only
  the boundary's own objects. Crawl jobs, audit runs, findings and
  recommendations created through a delegated call are genuine customer data
  created by the ordinary SEO path and are deliberately left in place.

## 7. Apply boundary

**State as of 2026-09-20, after the first controlled TEST run.** This section
previously said the whole set was unapplied. It is not; TEST migration history
is now the authoritative truth and it says otherwise.

| Migration | `Digi_SEO_Test` |
|---|---|
| `20260920120000_seo_brain_machine_boundary_identity.sql` | **applied** |
| `20260920120100_seo_brain_delegated_read_rpcs.sql` | **applied** |
| `20260920120200_seo_brain_actor_links.sql` | **applied** |
| `20260920120300_seo_brain_delegated_write_rpcs.sql` | **applied** |
| `20260920120400_seo_brain_stage2b_runtime_corrections.sql` | **applied** |
| `20260920120500_seo_brain_normalizer_locale_correction.sql` | **NOT applied** |

TEST stands at 46 local = 46 remote migrations through `20260920120300`. The
long-standing `20260720121000` (SSO identity bridge) discrepancy is resolved:
it was physically present but unrecorded, and was repaired as applied during
that run. **Do not repeat or undo that repair.**

Because the first four are applied and recorded, a defect in them is corrected
**forward**, in a new migration, never by editing the applied file. An edit to
an applied file would never run and would leave the database and the repository
disagreeing.

The verification script did **not** complete: it aborted in its prerequisite
section before any mutation, which is the behaviour it is designed for. The
Edge Function was not deployed, no actor or website links were created, no
crawl was requested, and production was untouched.

### The corrective migration: `20260920120400`

Additive. Creates no table, no policy and no capability.

1. **Host normalizer parity.** `seo_brain_normalize_host('not a url')` returned
   `'not a url'` where TypeScript returns `null`, because the authority pattern
   excluded `:[]/?#` and nothing else, so whitespace passed through as if it
   were a canonical host. The corrected function removes ASCII tab, LF and CR
   from the input, trims each end, and then **fails the parse on any remaining
   ASCII whitespace or C0/DEL control in the host or port.** The check runs on
   the authority after userinfo and path/query/fragment are removed, because
   those parts may legally contain a space and Digi Brain normalizes them
   successfully. Signature, `IMMUTABLE`, security mode, `search_path` and grants
   are unchanged, and no canonical valid-host output moves.

   **The trim is asymmetric, and that is deliberate.** Independent review caught
   a fail-open defect in the first draft of this migration, while it was still
   unapplied anywhere: it trimmed **both** ends with `[[:space:][:cntrl:]]`, so
   `<NUL>example.com`, `<SOH>example.com` and `<DEL>example.com` came back as a
   clean `example.com` while TypeScript returns `null` for all three. The twin
   is asymmetric because it calls JS `String.trim()` on the raw value and only
   then prefixes `https://`, so the URL parser's own leading strip never reaches
   the start of the caller's string.

   | End | Class | Why |
   |---|---|---|
   | Leading | `chr(9)` to `chr(13)` plus `chr(32)` | Exactly JS `String.trim()`'s ASCII set, written out. A leading C0 control or DEL is **not** trimmed; it reaches the host and fails the parse. |
   | Trailing | `chr(1)` to `chr(32)` | After prefixing, the caller's tail **is** the parser's tail, so the parser's C0-control-or-space strip applies. DEL is excluded on purpose: it is not a C0 control, so the parser does not strip it either. |

   One input is not comparable and is stated rather than hidden: a **trailing
   NUL**, which TypeScript normalizes and the SQL class does not reach. It is
   unreachable in practice because PostgreSQL `text` cannot contain `chr(0)` at
   all, so the function can never be handed that value.

   The corpus in `normalize-host.test.ts`, the model in
   `normalize-host-sql-parity.test.ts` and Section 0 of the operator
   verification script all carry leading NUL/SOH/US/DEL, the trailing
   counterparts, and the FF/VT/CRLF cases. The verification script's
   prerequisite additionally probes for **both** mistakes, the original
   whitespace-admitting version and the symmetric-trim version, before it
   mutates anything.
2. **Privilege hardening** (below).
3. **Corrected bootstrap rationale**, recorded as SQL comments on the affected
   objects.

### The locale correction: `20260920120500`

`20260920120400` got the asymmetry right and the **character class** wrong. It
wrote the leading trim as the POSIX class `[[:space:]]`, assuming that equals JS
`String.trim()`'s ASCII set. The controlled TEST run of the verification script
disproved that in Section 0, before any mutation:

```
P0001: normalizer parity failed for "<US>example.com": expected <NULL>, got example.com
```

Measured on `Digi_SEO_Test` rather than assumed:

```sql
SELECT string_agg(i::text, ',' ORDER BY i)
  FROM generate_series(1,32) i WHERE chr(i) ~ '[[:space:]]';
--> 9,10,11,12,13,28,29,30,31,32
```

glibc classifies FS, GS, RS and US as space characters. JavaScript does not. So
a leading U+001C through U+001F was trimmed and a clean canonical host came back
for a value the twin rejects, which is the same fail-open shape as before, moved
to four different characters.

**The rule this establishes: a POSIX character class must never be used where
the result has to match JavaScript or WHATWG behaviour**, because membership is
decided by the database ctype and not by the standard being mirrored.

| Class | Form in `20260920120500` | Why |
|---|---|---|
| Leading trim | explicit `chr(9)-chr(13)`, `chr(32)` | Parity target. Must equal `String.trim()` exactly. |
| Trailing trim | explicit `chr(1)-chr(32)` | Parity target. Already explicit in `20260920120400`. |
| Forbidden in authority | explicit `chr(1)-chr(32)`, `chr(127)` **plus** `[:space:][:cntrl:]` | Rejection gate, not a parity target. The explicit floor makes the ASCII part locale-proof; the POSIX classes are **kept** because on this database they also reject U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. Dropping them would have silently started admitting hosts carrying non-ASCII whitespace, which is the exact direction these corrections exist to prevent. |

Corpus coverage now sweeps ASCII 9 to 13, 28 to 31, 32, SOH and DEL in four
positions each (leading, trailing, alone, inner), plus IPv4 and IPv6 literals,
in the TypeScript corpus, the SQL model and Section 0. The script prerequisite
probes for all three mistakes before it mutates anything.

**Known remaining normalizer divergences, recorded rather than hidden.** This
function is **not** a WHATWG URL parser and does not claim full fidelity to one.
It corrects whitespace and control handling and nothing else. The following are
pre-existing, were not introduced or widened by `20260920120400`, and **every
one of them fails closed**: SQL returns a value that can never equal a canonical
host Digi Brain would send, so the comparison refuses rather than mismatching.

| Input | SQL | TypeScript |
|---|---|---|
| `münchen.de` | `münchen.de` | `xn--mnchen-3ya.de` |
| `https://0x7f.1` | `0x7f.1` | `127.0.0.1` |
| `https://2130706433` | `2130706433` | `127.0.0.1` |
| `https://example.com\evil.com` | `example.com\evil.com` | `example.com` |
| `https://exa%20mple.com` | `exa%20mple.com` | `null` |
| `<NBSP>example.com` | unchanged | `example.com` |
| `//example.com` | `null` | `example.com` |
| `https://[::ffff:192.168.1.1]` | `[::ffff:192.168.1.1]` | `[::ffff:c0a8:101]` |

IDN conversion, IPv4 canonicalization and backslash-as-separator are not
implementable as small, safe corrections in PL/pgSQL, and writing a speculative
URL parser in SQL is explicitly out of scope for Stage 2B. An already-punycoded
host passes both sides identically, and no TEST website uses an IDN host today.

### Privilege hardening, and the decision per table

Supabase grants `ALL` on every new public table to `anon`, `authenticated` and
`service_role` by default, and `service_role` additionally bypasses RLS. The
first controlled TEST run found that `service_role` therefore held direct
`INSERT`/`UPDATE` on `seo_brain_actor_links`. That made the deliberate
revocation of `EXECUTE` on `seo_brain_bootstrap_actor_link` moot: the machine
could simply insert the row. Corrected in `20260920120400`.

| Table | Intended mutation path | Decision |
|---|---|---|
| `seo_brain_actor_links` | Human global admin, through RLS `TO authenticated`. No SECURITY DEFINER RPC behind it. | `service_role` loses `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`, **keeps `SELECT`** (`seo_brain_resolve_actor` is SECURITY INVOKER and reads it as `service_role`). `anon` loses everything. `authenticated` **keeps `SELECT`/`INSERT`/`UPDATE`** because that is the product path; loses `DELETE`. |
| `seo_brain_website_links` | Human workspace owner/admin, through RLS `TO authenticated`. | Same treatment, same reasoning. `service_role` keeps `SELECT` because all four delegated read RPCs are SECURITY INVOKER. |
| `seo_brain_operations` | The four SECURITY DEFINER delegated wrappers, which run as the table owner. A SELECT policy for members and **no write policy at all**. | No client role needs direct mutation, so `INSERT`/`UPDATE`/`DELETE` are revoked from all three. `SELECT` is left for `authenticated` (its member-read policy) and `service_role`. This is strictly narrower than the RLS posture already declared, so it removes no capability. |

`authenticated` was checked against the RLS path rather than revoked by reflex:
both authorization tables carry policies declared `TO authenticated` with no
definer RPC behind them, so revoking the table privilege would have broken the
intended human global-admin path outright.

The verification script asserts all of this with `has_table_privilege` before
any mutation, and additionally proves at runtime that a `service_role` session
cannot insert into either authorization table.

### Crawler worker availability

`execute.technical_audit` only enqueues. A crawl is executed by the
`crawler-worker` process, which polls; it is not started by this endpoint and
there is no Cloud Build or Cloud Run definition for it anywhere in the
repository. Without a worker running against the same project, a delegated
audit request is accepted, returns a real job id, and then stays `queued`
indefinitely. A genuine end to end acceptance test therefore needs an operator
run worker with `CRAWLER_ENV` **not** starting with `test`, so fixture
transport cannot engage and the crawl is real HTTP.

#### Crawler reality check (2026-09-20): a genuine crawler EXISTS

The first controlled TEST run flagged that `crawler-worker/package.json` still
describes the worker as *"Phase 1B skeleton - job lifecycle only; no crawling"*.
**That description is stale. The implementation disproves it.** Evidence, read
from the wired code path rather than from documentation:

* `crawler-worker/src/worker.ts:4,23,93` constructs and calls
  **`DiscoveryProcessor`**, not `SkeletonProcessor`. `src/processor.ts`
  (`SkeletonProcessor`, the genuine "no crawling" class) is **not referenced by
  the worker at all** and survives only as unused Phase 1B code.
* `src/discovery/discoveryProcessor.ts` runs the real Phase 1C/1D pipeline:
  `DiscoveryEngine` over robots.txt and sitemaps, `extractPageFacts` per page,
  `detectPageIssues` plus `detectSiteDuplicates`, then `publishJobResults`.
* `src/discovery/safeHttpTransport.ts` performs real HTTP over `node:http` /
  `node:https` with `DigibilitySEO-Crawler/0.1` as its user agent, redirect
  handling and IP/URL safety checks. It is the default transport;
  `FixtureTransport` is substituted **only** when `CRAWLER_FIXTURE_TRANSPORT` is
  set *and* `CRAWLER_ENV` starts with `test` (`src/config.ts:96-99`).

**Classification: A. A genuine crawler exists and can satisfy Stage 2B
acceptance.** The stale `package.json` description is a documentation defect,
not a missing capability, and is not a Stage 2B blocker.

> **Runtime defect found during acceptance on 2026-09-21, corrected in
> `20260920120500`'s follow-up commit (no migration).** The classification above
> was reached by reading the wired code path, and the code path is genuine. It
> was nonetheless UNRUNNABLE on Node 20 and later, which the code reading did
> not reveal and no test could see.
>
> **Symptom.** Every fetch failed with `network_error` and `http_requests: 0`,
> for `digibility.ai` and for a neutral control host alike. Crawl job
> `8e982ce8-3ac5-49a4-8d63-587047701c63` (audit run `ce6653de`) is the genuine
> record of that failure and is kept as evidence.
>
> **Root cause.** Since Node 20, address-family autoselection
> (`net.getDefaultAutoSelectFamily() === true`) calls a custom `lookup` with
> `{ all: true }` and expects an ARRAY of `{ address, family }` back.
> `safeLookup` in `crawler-worker/src/discovery/safeHttpTransport.ts` always
> replied with the single-address shape, so Node read `address` as `undefined`
> and raised `ERR_INVALID_IP_ADDRESS`, which `oneHop` reduced to an unexplained
> `network_error`. Real crawls last succeeded on 2026-07-15, so this is a
> runtime regression rather than a crawler that never worked.
>
> **Correction.** `safeLookup` now honours both callback shapes. Every candidate
> address is still classified before anything is returned and a single unsafe
> address still rejects the WHOLE target, so SSRF protection is unchanged and
> still fails closed. Disabling autoselection was used only as diagnostic
> evidence and deliberately NOT shipped: it would have hidden the contract break
> and given up IPv4/IPv6 fallback for every crawl.
>
> **Why no test caught it.** Every crawler test used `FixtureTransport`, so
> nothing exercised `safeLookup` against a real socket. Coverage added:
> `crawler-worker/test/safeLookup.test.ts` pins both callback shapes, multi
> address handling, IPv4/IPv6, and fail-closed rejection when any address is
> unsafe (with the unsafe entry placed last, so a filter-and-continue
> implementation would fail the test). A genuine non-fixture network test lives
> in `crawler-worker/test/integration/realTransport.test.ts`, run by
> `npm run test:integration` and kept out of the default offline suite.

Two operator conditions do apply, and both are ordinary configuration rather
than missing code:

1. **Job eligibility.** `DiscoveryProcessor` refuses any job whose idempotency
   key does not start with `CRAWLER_TEST_JOB_PREFIX` (default
   `PHASE16D-VERIFY-`) unless `CRAWLER_ALLOW_NON_TEST_JOBS=true`. The key the
   delegated wrapper hands the control plane is Brain's own
   `idempotencyKey` with `'@' || website_id` appended
   (`20260920120300`, `v_crawl_key`). So for acceptance either send a Brain
   `idempotencyKey` that starts with the configured prefix, or set
   `CRAWLER_ALLOW_NON_TEST_JOBS=true` in the TEST worker shell.
2. **Poll mode.** `src/index.ts:88-94` refuses `--mode=poll` unless
   `CRAWLER_ALLOW_NON_TEST_JOBS=true`, and its message still says "no real
   crawler processor exists yet", which is the same stale claim. Use
   `--mode=one-shot` with an eligible job, or set the flag.

### Genuine ownership verification for TEST acceptance

`execute.technical_audit` preserves the P1a verified-ownership requirement, so
Stage 2B acceptance needs a website whose `seo_ownership_verifications.status`
is genuinely `verified`. **That row is never to be manufactured**: seeding it,
updating it by hand, or relaxing the check would falsify the exact invariant the
acceptance is meant to prove. The only legitimate route is the existing locked
P1a DNS TXT path, end to end.

**Recommended TEST target: `digibility.ai`.**

| Item | Value |
|---|---|
| TEST project | `Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm` |
| `seo_websites.id` | `fb98d59c-0f7d-4724-9f60-9db385bf2592` |
| Host (`verification_host`) | `digibility.ai` |
| Canonical Brain host (`seo_brain_normalize_host`) | `digibility.ai` |
| Current verification state | **`failed`**, verified by direct query against `Digi_SEO_Test` on 2026-09-20. An earlier version of this table said `revoked` and was internally inconsistent: it dated the revocation to 2026-07-17 and then described a real `failed` / `dns_not_found` worker run on 2026-07-19, which is what actually left the row in its present state. `failed` and `revoked` are treated identically by the re-initiation path, so the procedure below is unaffected. |

It is the right target for one reason that matters more than convenience: it is
a domain the organization actually controls, so the required DNS TXT record can
be published legitimately. Every other website seeded on TEST
(`brainverify-a.test`, `r1-site-a.example`, `c2-site-a.example`,
`ui-seed-digibility.example`) sits under `.test` or `.example`, which are
reserved names that resolve nowhere and can never carry a real TXT record. **If
`digibility.ai`'s DNS is not available to this operator, there is no other
existing TEST website that can be genuinely verified, and that is a hard
blocker rather than something to work around.**

**How the path works.** `seo_ownership_verification_initiate` mints a CSPRNG
challenge token of the form `digibility-site-verification=<64 hex>` and stores a
`pending` row. `seo_ownership_verification_claim` (service role only) hands the
worker the record name `_digibility-site-verification.<verification_host>` and
that exact token as the expected value. The worker resolves TXT over real Node
DNS, joins each record's chunks per RFC 1035 and requires an **exact** match:
no substring, no case folding, no reconstruction across records. The result is
written by `seo_ownership_verification_record_result`, which validates the open
claim and appends one customer-visible event.

**Operator procedure. Steps 2 and 3 are external actions for a human; nothing
here is performed by this session.**

1. **Re-initiate**, as the workspace owner, signed in to the SEO TEST app: open
   the website's ownership panel and use **Verify ownership**. The current row
   is `failed`, which `seo_ownership_verification_initiate` treats exactly as it
   treats `revoked` (both restart with a fresh token), so this rotates a fresh
   token and returns the row to `pending`.
   Then read the token in a direct operator SQL session:

   ```sql
   SELECT id, verification_host, status,
          '_digibility-site-verification.' || verification_host AS txt_name,
          challenge_token AS txt_value
   FROM public.seo_ownership_verifications
   WHERE website_id = 'fb98d59c-0f7d-4724-9f60-9db385bf2592'::uuid
     AND method = 'dns_txt';
   ```

2. **Publish the DNS TXT record** at the organization's DNS provider for
   `digibility.ai`:

   | Field | Value |
   |---|---|
   | Name | `_digibility-site-verification` (so the FQDN is `_digibility-site-verification.digibility.ai`) |
   | Type | `TXT` |
   | Value | the `challenge_token` from step 1, verbatim |
   | TTL | short, for example 300 |

   Treat the token as a secret: do not paste it into a ticket, a screenshot or
   a chat log.

3. **Wait for propagation**, then confirm independently before spending a claim:

   ```bash
   dig +short TXT _digibility-site-verification.digibility.ai
   ```

4. **Run verify-once** from `crawler-worker/`, with `crawler-worker/.env`
   exported and `SUPABASE_SERVICE_ROLE_KEY` set for `Digi_SEO_Test`. Leave
   `CRAWLER_VERIFICATION_FIXTURE_DNS` unset so real DNS is used:

   ```bash
   npm start -- --mode=verify-once
   ```

   This is the same binary and the same RPC path already accepted on
   2026-07-19; only the DNS outcome differs.

5. **Evidence of success**, recorded from the database rather than from worker
   output alone:

   ```sql
   SELECT status, verified_at, last_checked_at, failure_reason
   FROM public.seo_ownership_verifications
   WHERE website_id = 'fb98d59c-0f7d-4724-9f60-9db385bf2592'::uuid;

   SELECT event_type, from_status, to_status, actor, created_at
   FROM public.seo_ownership_verification_events
   WHERE website_id = 'fb98d59c-0f7d-4724-9f60-9db385bf2592'::uuid
   ORDER BY created_at DESC LIMIT 3;
   ```

   A genuine pass is `status = 'verified'` with a non-null `verified_at`, a
   null `failure_reason`, and one new event row with `event_type = 'verified'`,
   `from_status = 'pending'` and `actor = 'worker'`. The worker exits 0 and logs
   `verify_once` with outcome `verified`; the challenge value, the lease token
   and the service-role key are never printed.

   A `failed` / `dns_not_found` outcome means the TXT record was not visible
   yet. Fix DNS and re-run; **never** write the verified row by hand.

### TEST acceptance: the real service-role delegated path

**Required before Stage 2B can be called verified. Not yet performed.**

The SQL verification script runs as the database owner. It proves the delegated
RPCs' logic, but it cannot prove the part that only exists over the wire: that a
real service-role PostgREST call reaches those RPCs and that the impersonation
inside them attributes the resulting work to the mapped human rather than to the
service identity. That is not something to simulate locally, and no local result
should be presented as if it covered it.

After an authorized TEST migration apply and Edge Function deployment, and with
a `crawler-worker` running against the same project, perform these steps in
order and record the actual values:

1. Create or confirm the website link for the Business and normalized host, and
   confirm `seo_brain_resolve_target` returns `resolved`.
2. Create or confirm the actor link through the operator bootstrap above, and
   record its `linked_by`.
3. Call the real machine endpoint over HTTP with the service-role-backed
   delegated path, not a local handler and not a mock port.
4. Request a genuine `execute.technical_audit` for that Business and host.
5. Capture the real `moduleOperationId` from the acknowledgement, and confirm
   `accepted` is `true`.
6. Query `public.seo_crawl_jobs` for that id and confirm the row exists and
   carries the expected `website_id`.
7. Assert `seo_crawl_jobs.requested_by` equals the SEO `auth.users` id the Brain
   actor is mapped to.
8. Assert that `requested_by` is neither NULL nor any service or system
   identity. A NULL or a service identity here means the impersonation did not
   take effect and the acceptance has failed.
9. Verify isolation: repeat the STATUS call for a different Business, and for a
   sibling website of the same Business, and confirm neither resolves this
   operation. Confirm the sibling website receives its own distinct
   `moduleOperationId` when the same `brainActionId` is used.

Until every one of these is recorded as passing, the service-role delegation
path is unproven, whatever the local suites report.

### Brain-side integration requirement: `accepted` is not optional

Recorded here so the Brain to SEO integration gate can enforce it. No Digi Brain
code is changed by Stage 2B.

A Brain caller of EXECUTE **must explicitly inspect `accepted`**. SEO reports a
legitimate precondition failure as a real acknowledgement carrying
`accepted: false` and its own `moduleStatus`, exactly as Contract v1 models it,
rather than as a thrown error that would discard the reason.
`ownership_not_verified`, `no_completed_audit` and `no_genuine_audit_evidence`
all arrive this way.

**An acknowledgement with `accepted: false` must never be interpreted as
successful execution, even when the HTTP exchange and the contract validation
both succeeded.** A caller that treats a 200 response as success, or that only
checks for a thrown error, will record work as started that SEO explicitly
declined to start. This will be enforced at the Brain to SEO integration gate.

## 8. Contract requirement requests

**CRR-7: per finding provenance and evidence. OPTIONAL, non blocking.**
`AnalysisFinding` carries `findingKey`, `title`, `observation`,
`recommendedAction` and `severity`, and `ModuleProvenance` sits at the response
level only. SEO holds real per issue evidence, `crawl_job_id`,
`source_issue_fingerprint` and `source_rule_version`, that has nowhere to go
when a single response mixes rule versions. SEO works around this today by
using the crawler fingerprint as `findingKey`, which preserves the evidence
anchor, and by omitting `generationMethod` when the rule version is not uniform
rather than overstating it. A future contract version could carry an optional
per finding provenance object.

**CRR-8: severity granularity. OPTIONAL, non blocking.**
`FINDING_SEVERITIES` is three valued; SEO audit issues are four valued
(`critical`, `high`, `medium`, `low`). SEO collapses `critical` onto `high`,
upward, since that is the only direction that cannot understate a finding. Brain
therefore cannot distinguish a critical issue from a high one. Recorded, not
requested: collapsing upward is safe and a fourth level is not worth a contract
change on SEO's account alone.

**No blocking contract requirements.** All five reconciliation amendments SEO
asked for in the Stage 0 readiness review are present in the frozen v1 and are
sufficient: `provenance`, `actorId`, `target_not_linked`, `moduleOperationId`
and the authenticity gate.

### Knowingly deferred, not defects to be rediscovered

Recorded so a later reviewer does not re-raise them as new. None is a blocker
for Stage 2B; each is either a contract-level question or work that belongs to a
different task.

* **CRR-7, per finding provenance.** Above.
* **CRR-8, severity granularity.** Above.
* **Recommendation authenticity is run level, not row level.** The gate proves
  the audit the generation derived from was genuine crawler evidence, and that
  each returned recommendation carries a stored `generation_method`. It does not
  tie an individual recommendation row back to an individual crawler finding.
* **Unicode and WHATWG normalizer edge parity.** `seo_brain_normalize_host`
  matches Brain's `normalizeWebsiteHost` case for case on the cases the shared
  test table covers. Full WHATWG URL parsing, internationalized domain names and
  punycode are not proven equivalent between the SQL and the TypeScript
  implementations.
* **No product UI for actor-link management.** Creation is the operator
  bootstrap in section 2; revocation is a direct statement. Deliberate.
* **No crawler-worker deployment infrastructure.** See "Crawler worker
  availability" above.
* **A14, the unrecorded `20260720121000` migration on `Digi_SEO_Test`.** A
  separate, unresolved SSO task. Untouched here, and a hazard for any
  `supabase db push`.
* **Broad project TypeScript configuration for Edge Functions.** `index.ts`
  targets Deno and is not covered by project `tsc`; the boundary test files
  carry a pre-existing union-narrowing pattern that a strict direct check
  flags. Neither affects the production modules, which check clean.
