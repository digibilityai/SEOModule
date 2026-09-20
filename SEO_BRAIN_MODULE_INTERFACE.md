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
| `analyse.technical_audit` | analyse | What did the crawler find | `seo_audit_issues` where `source='crawler'`, latest completed run | `measured_external` / `measured` |
| `execute.recommendations` | execute | Generate rule-based recommendations | `seo_recommendation_generate` | `calculated` / `derived`, `generationMethod` from the stored rows |
| `analyse.recommendations` | analyse | Current recommendation set | `seo_recommendations` where `is_current` and `generation_method` is not null | `calculated` / `derived` |

A STATUS poll reuses the originating `execute.*` key. There is no `status.*`
namespace.

Every response is `dataAuthenticity: "genuine"`. An execute that declines to
start work returns a genuine acknowledgement with `accepted: false` and SEO's
own `moduleStatus`, rather than an opaque error, so Brain can tell a blocked
precondition apart from a failure.

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
| `npm test` | see below |
| `npx tsc -b` | clean |
| `npm run build` | clean |
| `crawler-worker` suite | **74 passed**, unchanged |
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
  preserved verified-ownership requirement, a real `seo_crawl_jobs` id as the
  operation handle, truthful `requested_by`, idempotent replay, same-key STATUS
  correlation and a foreign operation id failing closed.
* `supabase/test/seo_brain_module_boundary_rollback_TEST_ONLY.sql`. Drops only
  the boundary's own objects. Crawl jobs, audit runs, findings and
  recommendations created through a delegated call are genuine customer data
  created by the ordinary SEO path and are deliberately left in place.

## 7. Apply boundary

**STOP. The entire Stage 2B migration set is UNAPPLIED and nothing should be
applied yet.** TEST integration is still pending.

Four migrations, in order:

1. `20260920120000_seo_brain_machine_boundary_identity.sql`
2. `20260920120100_seo_brain_delegated_read_rpcs.sql`
3. `20260920120200_seo_brain_actor_links.sql`
4. `20260920120300_seo_brain_delegated_write_rpcs.sql`

Before any apply to `Digi_SEO_Test`:

1. Run all four plus the verification script against a **local or fresh**
   project first. That is not possible in the current environment.
2. Independently recheck TEST migration history. The known situation is that
   `20260720121000` (SSO identity bridge) is physically present on
   `Digi_SEO_Test` but unrecorded in migration history. A `supabase db push`
   would encounter it. That remains a separate, unresolved SSO task per
   `SEO_DECISIONS.md` A14 and was deliberately not touched here.
3. Review all four migrations explicitly.
4. Reach an explicit apply approval.

### Crawler worker availability

`execute.technical_audit` only enqueues. A crawl is executed by the
`crawler-worker` process, which polls; it is not started by this endpoint and
there is no Cloud Build or Cloud Run definition for it anywhere in the
repository. Without a worker running against the same project, a delegated
audit request is accepted, returns a real job id, and then stays `queued`
indefinitely. A genuine end to end acceptance test therefore needs an operator
run worker with `CRAWLER_ENV` **not** starting with `test`, so fixture
transport cannot engage and the crawl is real HTTP.

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
