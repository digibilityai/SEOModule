# SEO Module: Digi Brain Module Contract v1 interface (Stage 2B)

**Status:** implemented on branch `feat/seo-brain-module-contract-stage2b`.
**Nothing has been applied to any Supabase project and nothing has been deployed.**

This document describes the SEO side of the machine boundary. The contract
itself is owned by Digi Brain and is frozen at commit `0159a3f`
(`feat(modular-arch): Stage 1, generic Module Contract v1`, PR #147),
`server/modules/types.ts`. SEO does not extend it.

## 1. What is exposed

Four read capabilities, all in the `analyse` family, all website scoped:

| Capability key | Answers | Genuine source | Provenance reported |
|---|---|---|---|
| `analyse.target_linkage` | Is this Business linked to exactly one SEO website for this host | `seo_brain_website_links` | `customer_provided` / `declared` |
| `analyse.ownership_verification` | Is domain ownership verified | `seo_ownership_verifications` (real DNS TXT) | `measured_external` / `measured` once a check has run, `calculated` / `derived` when none has |
| `analyse.crawl_findings` | What did the crawler actually find | `seo_audit_issues` where `source='crawler'`, latest completed run | `measured_external` / `measured`, `generationMethod` = crawler rule version |
| `analyse.current_recommendations` | What does SEO currently recommend | `seo_recommendations` where `is_current` and `generation_method` is not null | `calculated` / `derived`, `generationMethod` = stored value, `rule_based_v1` today |

Every response is `dataAuthenticity: "genuine"`. Anything that could not be
reported as genuine is not exposed at all.

Deliberately **not** exposed, and refused with `unsupported_capability`:
`seo_run_audit` (a stub that creates a run row and no findings), competitor
benchmarking (hash derived estimates), Page Performance (`manual_seed` only,
no GSC or GA4 integration exists), Decline Diagnosis (storage with no engine),
AI Visibility (manual and import only), Roadmap (no backend at all), Content
Studio publishing, off page execution, manual completion, expert routing, and
mixed provenance reports.

## 2. Blocked write capabilities

`execute.technical_crawl` and `analyse.recommendation_generation` are approved
in principle and are **not implemented**. They are absent from the capability
declaration, so Digi Brain receives `unsupported_capability`, which the contract
defines as a refusal rather than a failed attempt.

**The exact missing mapping.** Both underlying RPCs, `public.seo_crawl_request`
and `public.seo_recommendation_generate`, authorize on `auth.uid()`, require an
`owner`, `admin` or `team_member` role in the website's workspace, and write
`created_by` plus append only activity rows. Digi Brain's `actorId` identifies a
human in the **Digi Brain** Supabase project. SEO users are rows in the **SEO**
project's own `auth.users`. Nothing in this repository maps one to the other:

* `public.seo_identity_profiles` is keyed on the SEO user id, holds no Brain
  identifier, and is referenced by zero lines of application code.
* `public.seo_workspaces.core_profile_id` and `core_workspace_id` are unused
  nullable seams, referenced by zero lines of application code.
* The SSO bridge establishes a browser session for a human through
  `verifyOtp`. It is single use and interactive, and it is not an identity map.

Contract v1 states `actorId` is "never a credential, never trusted by this
boundary as authorization", so holding the machine secret cannot stand in for
the acting human. Inferring the actor by email, by "the workspace owner", or by
reusing the link's `linked_by` would write a false `created_by` into an audit
trail the product presents as evidence. That is why no mapping was invented.

**What would unblock this:** one human authorized actor link, equivalent in
shape and spirit to `seo_brain_website_links`, associating a Brain actor
identifier with an SEO `auth.users` id, established by a human in each
direction rather than inferred. That is a separate decision with its own
identity and consent implications and it is not in this stage's scope.

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
* Authenticated by a shared secret in the `x-digibility-module-secret` header,
  compared in constant time. A missing or short server side secret fails closed
  with `module_unavailable` rather than serving open.
* `GET` returns the capability declaration, and is authenticated too: the set
  of capabilities SEO exposes is not public.
* `POST` carries one Contract v1 envelope.
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
| `npm test` | **144 passed**, 10 files. 48 pre-existing plus 96 new. |
| `npx tsc -b` | clean |
| `npm run build` | clean |
| `crawler-worker` suite | **74 passed**, unchanged |
| SQL migrations | **NOT executed.** No Postgres, Docker or Supabase local runtime is available in this environment. |

The SQL is therefore **statically reviewed but unverified**. It must be run
before anyone relies on it. Two operator scripts are provided:

* `supabase/test/seo_brain_module_boundary_verification.sql`, self seeding and
  self cleaning, covering normalizer parity case for case against
  `normalize-host.test.ts`, trigger derivation, the full resolution matrix,
  revocation, host change, inactive website, both authenticity gates, no
  sibling and no cross tenant substitution, the grant matrix and link RLS.
* `supabase/test/seo_brain_module_boundary_rollback_TEST_ONLY.sql`.

## 7. Apply boundary

**STOP. Nothing has been applied and nothing should be applied yet.**

Before any apply to `Digi_SEO_Test`:

1. Run both new migrations plus the verification script against a **local or
   fresh** project first. That is not possible in the current environment.
2. Independently recheck TEST migration history. The known situation is that
   `20260720121000` (SSO identity bridge) is physically present on
   `Digi_SEO_Test` but unrecorded in migration history. A `supabase db push`
   would encounter it. Whether to repair that history, or to apply these two
   migrations by a path that does not touch it, is an unresolved decision that
   belongs to a separate SSO task per `SEO_DECISIONS.md` A14.
3. Review both migrations explicitly.
4. Reach an explicit apply approval.

The two migrations are purely additive and the rollback script is clean, but
that is an argument for reversibility, not for applying without the gate.

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
