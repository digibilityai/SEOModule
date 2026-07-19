# Supabase Migration — Stage 6: Off-Page Authority + AI Visibility/GEO (Notes)

Phase 15A — implementation notes for the Stage 6 migrations. **The SQL has been
authored, dry-run on TEST + rolled back (§7b), APPLIED to the disposable TEST
project `Digi_SEO_Test` and structurally verified (§7c), SMOKE-TESTED PASS +
self-cleaned (§7d), and UI-SEEDED + verified (§7e). It is still NOT
service-wired.** Additive only; no existing migration or app code was modified
(the smoke-test and seed bugs found during authoring were fixed in the test/seed
files, not the migrations). Production untouched.

> Built strictly to the locked spec in
> `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_PLAN.md` §0 (D1–D7). Where
> this task's "Expected workflow design" hints differed from the locked plan,
> the **locked plan + the existing frontend types won** — see §7 (Deviations).

---

## 1. What was created

| File | Contents |
| --- | --- |
| `supabase/migrations/20260711120017_seo_stage6_authority_opportunities.sql` | `seo_authority_opportunities` + indexes + D7 soft-dup partial unique + `updated_at` trigger + RLS |
| `supabase/migrations/20260711120018_seo_stage6_authority_campaigns.sql` | `seo_authority_campaigns` (no `opportunity_ids[]`, no `progress_percentage`) + indexes + trigger + RLS |
| `supabase/migrations/20260711120019_seo_stage6_authority_campaign_children.sql` | `seo_authority_campaign_tasks` + `seo_authority_campaign_opportunities` (junction) + same-workspace/website integrity trigger + indexes + trigger + RLS |
| `supabase/migrations/20260711120020_seo_stage6_authority_activity.sql` | `seo_authority_activity` (append-only audit) + the two transition RPCs `seo_authority_opportunity_transition` / `seo_authority_campaign_transition` + grants |
| `supabase/migrations/20260711120021_seo_stage6_ai_prompt_tracking.sql` | `seo_ai_prompt_tracking` (time-series, `observed_on`) + indexes + trigger + RLS |
| `supabase/migrations/20260711120022_seo_stage6_ai_content_gaps.sql` | `seo_ai_content_gaps` + indexes + trigger + RLS |
| `supabase/migrations/20260711120023_seo_stage6_ai_mentions.sql` | `seo_ai_mentions` + indexes + trigger + RLS |

Continues the timestamp sequence after Stage 5 (`…120016`). **23 migration
files total** now on disk.

---

## 2. Tables (8) + RPCs (2)

**Tables:** `seo_authority_opportunities`, `seo_authority_campaigns`,
`seo_authority_campaign_tasks`, `seo_authority_campaign_opportunities`
(junction), `seo_authority_activity` (append-only), `seo_ai_prompt_tracking`
(time-series), `seo_ai_content_gaps`, `seo_ai_mentions`.

**RPCs (`SECURITY DEFINER`, `SET search_path = public`, `GRANT EXECUTE … TO
authenticated`):** `seo_authority_opportunity_transition(p_opportunity_id, p_action, p_note)`,
`seo_authority_campaign_transition(p_campaign_id, p_action, p_note)`.

**Trigger function:** `seo_authority_campaign_opportunity_integrity()` (junction
same-workspace/website guard) — `SECURITY DEFINER`.

All 8 tables carry `workspace_id`/`website_id`/`website_url` (children too, for
RLS uniformity — the Stage 5 evidence precedent). Every operational table has
`created_by`/`created_at`; mutable tables have `updated_at` + a `set_updated_at`
trigger (junction + activity are create-only/append-only → no `updated_at`).

---

## 3. Locked decisions, as implemented

- **D1 (junction):** `seo_authority_campaign_opportunities` with
  `PRIMARY KEY (campaign_id, opportunity_id)`, both FKs `ON DELETE CASCADE`, is
  the source of truth. No `opportunity_ids[]` on the campaign. A `BEFORE
  INSERT/UPDATE` integrity trigger rejects cross-workspace/website links.
- **D2 (mentions):** `seo_ai_mentions` normalized rows with `mention_type ∈
  (brand, competitor, citation_source)` + `is_our_site` for citation reporting.
- **D3 (no client writes):** every write policy is
  `seo_role_in(owner/admin/team_member) OR seo_is_global_admin()`. No policy
  references `client`. Clients read via the SELECT policies only. The RPCs reject
  clients in-function.
- **D4 (time-series prompts):** `observed_on date NOT NULL DEFAULT current_date`;
  **no `prompt_text` uniqueness**; indexed by `(website_id, observed_on DESC)` +
  `visibility_status`/`topic`/`source`.
- **D5 / D5a (guarded RPCs + activity):** off-page status moves only via the two
  transition RPCs, which enforce the exact action→status matrices from plan §0,
  check role inside the function (base = owner/admin/team_member; opportunity
  `reject` and campaign `approve`/`reject` = owner/admin only), and append a
  `seo_authority_activity` row (`subject_type`, `from_status`, `to_status`,
  `activity_type`, `actor_role_snapshot`, `note`). The `start` action is only
  reachable from `approval_required`/`expert_review_requested` — the
  external-action-needs-approval guarantee (requirement 7).
- **D6 (derived progress):** no `progress_percentage` column on campaigns;
  derived from `seo_authority_campaign_tasks` in the later service phase.
- **D7 (soft dup guard):** partial unique index on
  `(website_id, opportunity_type, lower(target_url))` **WHERE `target_url IS NOT
  NULL` AND status in the active set** — terminal/URL-less opportunities never
  block; never dedupes by title. Nullable `target_domain` added for future
  grouping (not in the unique key).

---

## 4. RLS model (all 8 tables)

- **SELECT:** `is_seo_workspace_member(workspace_id) OR seo_is_global_admin()`
  (member incl. client can read).
- **Write:** operational tables use one `FOR ALL` policy =
  `seo_role_in(owner/admin/team_member) OR seo_is_global_admin()` (USING + WITH
  CHECK). Clients cannot write.
- **`seo_authority_activity` is append-only:** SELECT (members) + a single
  `FOR INSERT` policy (managers); **no UPDATE/DELETE policy** anywhere → rows are
  immutable. The transition RPCs (SECURITY DEFINER) also insert here.
- No `profiles.role`, no new auth model, no service-role dependency.

Verified counts: 8 `ENABLE ROW LEVEL SECURITY`, 8 SELECT policies, 7 `FOR ALL`
write policies, 1 `FOR INSERT` (activity), **0** UPDATE/DELETE policies.

---

## 5. Safety guarantees encoded

- No automation/outreach/review generation — tables store opportunities +
  decisions; nothing executes. `spam_risk_flags` + `avoided` record steering
  *away* from risk.
- `requires_approval` defaults `true`; the opportunity RPC blocks `start` before
  approval/expert review.
- AI Visibility is observed/manual/imported: `source ∈ (manual_seed, import,
  system)` on all AI tables; `observed_on` is a passive date. No LLM, crawler,
  GSC/GA4, external API, or cron anywhere.
- No guaranteed-ranking field; impact/effort/risk are `low/medium/high`
  estimates only.

---

## 6. Constraints & indexes (highlights)

- CHECKs on every enum-like column (opportunity_type/status/impact/effort/risk/
  fix_owner/source; campaign approval_status/owner/source; task owner_type;
  activity subject_type + "exactly one subject"; prompt visibility_status/source;
  content-gap priority/status/source; mention mention_type/sentiment/prominence/
  source). `spam_risk_flags <@ ARRAY[…]` element-containment.
- Unique: junction PK `(campaign_id, opportunity_id)`; task
  `(campaign_id, position)`; opportunity D7 active-only partial unique.
- FK + filter indexes on `workspace_id`/`website_id`/status/type/source/
  created_at/observed_on and each child FK.

---

## 7. Deviations from the raw task hints (deliberate, documented)

1. **Status vocabularies kept 1:1 with the locked plan + frontend types.** The
   task's "Expected workflow design" floated alternative statuses (opportunity:
   `needs_review`/`approved`/`archived`; campaign: `awaiting_approval`/
   `in_progress`/`paused`/`completed`/`cancelled`/`archived`). These were **not**
   adopted: the locked plan §0 matrices and the existing frontend
   `OffPageOpportunityStatus` / `CampaignApprovalStatus` types (`src/types/offpage.ts`)
   are the ground truth, and diverging would break the later 1:1 service mapping.
   Implemented statuses are exactly the plan/frontend sets. (If a richer campaign
   *execution* lifecycle is wanted later, it is an explicit future change to both
   the type and this schema.)
2. **File-split order:** the plan drafted activity+RPCs as the last file
   (`…120023`); this task's explicit filenames place activity at `…120020`
   (before the AI tables). Implemented per the task's filenames — valid because
   the RPCs depend only on the off-page tables (17/18) + the activity table, not
   on any AI table. `ai_mentions` is `…120023`.
3. **Additive optional fields** were added per the task's "Include fields for"
   lists where they don't conflict with the plan/types: `target_domain`,
   `recommended_next_action`, `notes` (opportunities); `campaign_type`,
   `started_at`, `completed_at` (campaigns); `task_type`, `owner_type`,
   `due_date`, `completed_at`, `external_action_required` (tasks); `brand_position`
   (prompt tracking); `gap_type`, `status` (content gaps); `entity_url`,
   `citation_url`, `is_our_site`, `mention_position`, `sentiment`, `prominence`
   (mentions). All nullable/defaulted — the frontend ignores extra columns.
4. **Activity table:** carries both the plan's two nullable FKs
   (`opportunity_id`/`campaign_id`, exactly-one CHECK) **and** the task's
   `subject_type` column (kept consistent by the CHECK), plus `activity_type`
   (the transition action) and `actor_role_snapshot`. `created_by` is the actor.

---

## 7a. Dry-run wrapper preparation + static validation (Phase 15A.1)

**Status: dry-run wrapper PREPARED + statically validated.** A transaction-wrapped
dry-run helper was built and the Stage 6 SQL was statically reviewed against the
Stage 1 dependencies. **This was the preparation step; the actual execution result
is recorded in §7b below.**

**Wrapper file:** `supabase/test/seo_stage6_dry_run_wrapper_TEST_ONLY.sql`
(test helper, **not** a migration, **not** seed). Shape:
`BEGIN;` → Stage 1-5 prerequisite guard → the **full contents of all 7 Stage 6
migration files inlined in order** (`…120017`–`…120023`) → in-transaction
verification SELECTs (CHECK 1–6) + a `DO $verify$` summary guard that RAISEs
unless every count matches → `ROLLBACK;`. Because Postgres DDL is transactional,
the final `ROLLBACK` removes every created object — **nothing from Stage 6 remains
applied** after a run.

**Why a paste-in wrapper:** the build environment has **no `psql`, no local
Postgres, and no Docker**, so a local dry-run could not be run there; the Supabase
CLI is present but a local stack needs Docker, and pushing to the remote TEST
project is out of scope for a dry-run (`supabase db push` is prohibited). Per the
task's fallback, the wrapper was prepared for a human to paste into the disposable
TEST project's SQL Editor — which was then done (§7b).

**Static validation performed (no defect found):**
- All 8 tables, 2 transition RPCs, and the junction integrity trigger/function are
  created by the inlined SQL; timestamp order `…120017`→`…120023` satisfies every
  dependency (junction after opportunities+campaigns; activity+RPCs after
  opportunities+campaigns; mentions/gaps after prompt tracking).
- Stage 1 dependencies confirmed to exist with matching names/signatures:
  `set_updated_at()`, `is_seo_workspace_member(uuid,uuid)`,
  `seo_role_in(uuid,text[],uuid)`, `seo_is_global_admin(uuid)`, and
  `seo_workspace_members(user_id, seo_role, status)` (the columns the RPCs read).
- Dollar-quoting is balanced and the wrapper's `$preflight$`/`$verify$` tags do
  not collide with the migrations' `$$` function bodies.
- RLS/policy shape matches the intended model: 8 `ENABLE ROW LEVEL SECURITY`,
  8 SELECT policies, 7 `FOR ALL` write policies, 1 `FOR INSERT` (activity),
  **0** UPDATE/DELETE policies — the wrapper's `DO $verify$` guard asserts exactly
  these counts.
- Note: the transition-RPC / integrity-function **bodies** are only syntax-checked
  at `CREATE` time (plpgsql defers column/row resolution to first execution), so a
  dry-run confirms structure; run-behavior (legal/illegal transitions, role
  gating, cross-workspace rejection) is covered by the later `99999999-` smoke
  test (§9), not by this dry-run.

---

## 7b. Dry-run EXECUTION checkpoint (Phase 15A.2) — PASSED on TEST + rolled back

**Status: dry-run EXECUTED successfully on the disposable TEST Supabase project
and ROLLED BACK. Engine-dry-run validated on TEST. Still NOT applied, NOT
smoke-tested, NOT seeded, NOT wired. Production untouched.** The wrapper
(`supabase/test/seo_stage6_dry_run_wrapper_TEST_ONLY.sql`) was run in the TEST
project's SQL Editor and completed cleanly.

**Wrong-project guard fired first — a positive safety result.** The wrapper was
**first accidentally run against the wrong project**. It **failed immediately at
the Stage 1–5 prerequisite guard** because the Stage 1–5 objects
(`seo_workspaces` / `seo_websites` / `seo_workspace_members` / the Stage 1 RLS
helpers) were missing there. This is the intended behavior: the `DO $preflight$`
guard raised and the transaction aborted before creating anything, so the
wrong-project run left **no Stage 6 objects behind**. The guard did exactly its
job — it prevented an out-of-order / wrong-target run.

**Correct TEST project — dry-run passed.** After switching to the correct
disposable TEST project (the one with Stages 1–5 already applied, `…120001`–
`…120016`), the wrapper ran to completion. The in-transaction verification
confirmed the expected Stage 6 object set was created:
- **8 tables** — `seo_authority_opportunities`, `seo_authority_campaigns`,
  `seo_authority_campaign_tasks`, `seo_authority_campaign_opportunities`,
  `seo_authority_activity`, `seo_ai_prompt_tracking`, `seo_ai_content_gaps`,
  `seo_ai_mentions`.
- **3 functions total** — the **2 transition RPCs**
  (`seo_authority_opportunity_transition`, `seo_authority_campaign_transition`)
  **+ 1 junction integrity function**
  (`seo_authority_campaign_opportunity_integrity`).

The transaction then hit the closing `ROLLBACK;`, so every created object was
undone.

**Rollback sanity-check — clean.** The post-run sanity-check query (Stage 6
tables remaining after rollback) returned **“Success. No rows returned”** — i.e.
**no Stage 6 tables persisted**. Nothing from Stage 6 remains applied on the TEST
project.

**Conclusion:** Stage 6 SQL is **engine-dry-run validated on TEST and rolled
back**. This confirms the DDL is engine-valid and the objects/RLS/policies/RPCs/
trigger all create cleanly on top of Stages 1–5. It does **not** mean Stage 6 is
applied, smoke-tested, seeded, or wired — run-behavior (legal/illegal transitions,
role gating, cross-workspace rejection) is still covered only by the later
`99999999-` smoke test (§9), which has not been run.

---

## 7c. TEST APPLY checkpoint (Phase 15A.3) — APPLIED to TEST + structurally verified

**Status: the 7 Stage 6 migrations are APPLIED to the disposable TEST project and
structurally verified. Still NOT smoke-tested, NOT seeded, NOT service-wired.
Production untouched.**

**Target project (verified before apply):** `Digi_SEO_Test` (ref
`snyzotgwwfomgafrsvfm`) — not production. Pre-apply verification via
`supabase migration list --linked` + `supabase db query --linked` confirmed:
Stages 1–5 (`…120001`–`…120016`) already applied on the remote; Stage 6
(`…120017`–`…120023`) **not** yet applied; the four Stage 1–5 sentinel objects
(`seo_workspaces`, `seo_websites`, `seo_page_inventory`, `seo_decline_diagnoses`)
present (4/4); zero Stage 6 tables present. A `supabase db push --dry-run --linked`
confirmed the pending set was **exactly the 7 Stage 6 files** — nothing unrelated.

**Apply method:** `supabase db push --linked` (normal Supabase migration workflow,
against the linked TEST project). All 7 migrations applied cleanly; the only output
was expected `NOTICE … does not exist, skipping` lines from the idempotent
`DROP TRIGGER/POLICY IF EXISTS` guards that precede each `CREATE`. `Finished
supabase db push.` (exit 0).

**Migration versions applied:** `20260711120017`, `20260711120018`,
`20260711120019`, `20260711120020`, `20260711120021`, `20260711120022`,
`20260711120023` — all now present in the remote migration history.

**Structural verification (via `supabase db query --linked`, read-only):**
| Check | Expected | Actual |
| --- | --- | --- |
| Stage 6 tables present | 8 | **8** |
| RLS enabled on those tables | 8 | **8** |
| Stage 6 functions (`seo_authority_campaign_opportunity_integrity`, `seo_authority_opportunity_transition`, `seo_authority_campaign_transition`) | 3 | **3** |
| Junction integrity trigger `trg_seo_authority_camp_opp_integrity` | 1 | **1** |
| SELECT policies | 8 | **8** |
| `FOR ALL` write policies | 7 | **7** |
| `seo_authority_activity` INSERT policy | 1 | **1** |
| `seo_authority_activity` UPDATE/DELETE policies | 0 | **0** |
| Rows across all 8 tables (no seed) | 0 | **0** (all 8 empty) |

**Smoke test: NOT yet authored or run.** The `99999999-` Stage 6 smoke test (plan
§11) has not been written or executed, so run-behavior — legal/illegal transitions,
manager-only campaign approve/reject, opportunity `start`-after-approval gating,
the junction cross-workspace rejection, client read-only enforcement, append-only
activity, CHECK/uniqueness rejections, cascades — is **structurally present but not
behaviorally verified**. That is the next task.

---

## 7d. SMOKE-TEST checkpoint (Phase 15A.4) — PASSED on TEST + self-cleaned

**Status: the Stage 6 smoke test was authored, run on the disposable TEST project
`Digi_SEO_Test`, and PASSED. It self-cleaned (teardown removed its own rows; all 8
Stage 6 tables returned to 0 rows). Stage 6 remains NOT seeded and NOT
service-wired. Production untouched.**

**Test file:** `supabase/test/seo_stage6_offpage_ai_visibility_smoke_test.sql`
(test helper — not a migration, not seed). Uses the `99999999-` UUID prefix
(unused by any prior stage), **reuses the 5 shared TEST auth users**
(owner/admin/team/client/nonmember), and follows the Stage 4/5 pattern: a
`_seo6_login()` helper + `SET LOCAL ROLE authenticated` inside `BEGIN … ROLLBACK`
(or `COMMIT` for persistent positives) so RLS is genuinely enforced (the run role
is `postgres`/BYPASSRLS otherwise). It PRE-CLEANS at the top and TEARS DOWN at the
end (deletes only its two `99999999-` workspaces, which cascade to all its rows),
so it is safe to re-run and leaves nothing behind except the shared helper users.

**Execution:** run via `supabase db query --linked -f …` against TEST. Final output
`STAGE 6 OFF-PAGE + AI VISIBILITY SMOKE TEST PASSED`; post-run verification
confirmed 0 `99999999-` workspaces and 0 rows across all 8 Stage 6 tables, helper
`_seo6_login` dropped, 5 auth users retained. (In the Supabase SQL Editor the
per-assertion PASS/FAIL NOTICEs are visible in the Messages tab.)

**Behavior checks that passed (A–K):**
- **A/B** — setup (two workspaces, members, three websites) + positive manager
  inserts on **all 7 writable tables** (opportunities, campaigns, tasks, junction,
  prompt tracking, content gaps, mentions) as owner/admin/team_member.
- **C** — RLS: owner/admin/team/client all READ; **client is read-only** (INSERT
  raises, UPDATE/DELETE affect 0 rows); **nonmember fully isolated** (0 rows,
  INSERT denied).
- **D** — opportunity RPC: legal path `suggested→shortlisted→approval_required→
  in_progress→completed`; illegal `start`-from-`suggested` rejected; terminal
  `completed` cannot be reject-reopened; `reject` is owner/admin-only (team_member
  raises, owner succeeds); client + nonmember RPC calls raise; **4 activity rows
  written with `actor_role_snapshot='team_member'` and correct from/to** (`start`
  = approval_required→in_progress).
- **E** — campaign RPC: `submit_for_approval` (team) → `approve` (owner);
  team_member `approve` raises (manager-only); `reject`+`return_to_draft` (admin);
  invalid `approve`-from-`draft` rejected; client cannot transition; activity rows
  carry `subject_type='campaign'`.
- **F** — junction: valid link succeeds; **duplicate link rejected by PK**;
  **cross-workspace and cross-website links rejected by the integrity trigger**;
  deleting a campaign cascades its tasks/junction/activity to 0; deleting an
  opportunity removes its junction rows while campaigns remain.
- **G** — D7 soft-dup guard: duplicate **active** opportunity (same
  website+type+`lower(target_url)`) rejected; **URL-less** opportunities repeat
  freely; a **terminal (`avoided`)** duplicate URL does **not** block a future
  active one.
- **H** — prompt tracking is time-series: the **same `prompt_text` on a different
  `observed_on` is allowed** (no uniqueness); invalid `visibility_status` /
  `source` / `brand_position` (<1) rejected.
- **I** — content gap links to a prompt; mentions insert for **brand /
  competitor / citation_source**; invalid `mention_type` / `source` / `sentiment`
  rejected; **deleting a prompt cascades its mentions and SET NULLs the linked
  gap** (gap survives).
- **J** — append-only activity: manager INSERT allowed; client INSERT denied;
  **UPDATE/DELETE blocked for everyone** (no policy → 0 rows); RPC-created rows
  persist.
- **K** — final end-state re-assertion (`a1=completed`, `a3=rejected`,
  `c1=approved`, junction=1, prompt time-series=2) + clean teardown sanity (0 rows
  remain).

**Smoke-test bugs found + fixed during authoring (NOT migration defects — no
Stage 6 migration SQL was changed):**
1. Two INSERTs (`seo_ai_mentions`, `seo_ai_content_gaps` in the prompt-delete
   fixture) were missing the `website_url` value (column/value count mismatch).
2. A `max(uuid)` aggregate misuse (uuid has no `max()`); replaced with a direct
   single-row `SELECT … INTO`.
3. Transaction-durability structuring for the `db query --linked` runner (it
   frames the whole script as one transaction, so an explicit `ROLLBACK` discards
   uncommitted bare inserts back to the last `COMMIT`): the re-checked time-series
   row plus the pre-clean and teardown were wrapped in explicit `BEGIN … COMMIT`.

**Acceptable notes / skips:** the run role via the Management API / SQL Editor is
`postgres` (BYPASSRLS), so RLS is exercised only inside the `SET LOCAL ROLE
authenticated` blocks — bare top-level statements run privileged by design (they
are fixtures, matching every prior stage's smoke test). No `spam_risk_flags`
element-CHECK negative case is included as a dedicated assertion (the array
containment CHECK is covered structurally); it can be added later if desired. No
seed rows are left behind — this is a behavior test, not a seed.

---

## 7e. UI SEED checkpoint (Phase 15A.5) — applied + verified on TEST

**Status: the Stage 6 UI seed extension was created, applied to the disposable
TEST project `Digi_SEO_Test`, and verified (idempotent re-run confirmed). Stage 6
is now backend-complete on TEST (applied + structurally verified + smoke-tested +
UI-seeded) but remains NOT service-wired. Production untouched.**

**Seed file:** `supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql`
(data seed — not a migration, not a correctness test). **Guide:**
`SUPABASE_STAGE6_OFFPAGE_AI_VISIBILITY_SEED_EXTENSION_GUIDE.md`.

- **Prefix `a6000000-`** (unused by base seed `44444444-`, Stage 4 `66666666-`,
  Stage 5 `88888888-`, or any smoke test) — cannot collide.
- **Attaches to the existing base UI seed** workspace
  `44444444-0000-0000-0001-000000000001` / website
  `44444444-0000-0000-0002-000000000001` (`https://ui-seed-digibility.example`);
  creates no new workspace/website.
- **`created_by` is DERIVED** from the base workspace's `seo_workspace_members`
  (owner + team_member) — no manual UUID paste; no `auth.users` writes.
- **Fails fast** if the base UI seed or the Stage 6 tables are missing.
- **Idempotent** (`ON CONFLICT DO NOTHING`); re-run confirmed identical counts.
- **All `source = 'manual_seed'`**; no crawler/GSC/GA4/LLM/scraping/cron/outreach/
  review-generation/backlink-automation/external-API. `avoided`/`rejected` rows
  with `spam_risk_flags` demonstrate steering away from risky tactics.

**Verified counts on TEST** (via `supabase db query --linked`):

| Table | Rows | Notable coverage |
| --- | --- | --- |
| `seo_authority_opportunities` | **9** | all 7 types; all 8 statuses; 2 safety rows (avoided/rejected + spam flags); URL + URL-less |
| `seo_authority_campaigns` | **4** | draft / pending_approval / approved / rejected |
| `seo_authority_campaign_tasks` | **11** | complete/incomplete; external_action_required T/F; owner_type variety |
| `seo_authority_campaign_opportunities` | **6** | junction links (integrity passes) |
| `seo_authority_activity` | **5** | demo history (opportunity + campaign) |
| `seo_ai_prompt_tracking` | **9** | all 4 visibility statuses; a 3-point time-series (same prompt_text) |
| `seo_ai_content_gaps` | **6** | priority low/med/high; status open/planned/addressed/dismissed |
| `seo_ai_mentions` | **13** | brand ×4 / competitor ×5 / citation_source ×4; our-site + source citations |

**One seed bug found + fixed during authoring (NOT a backend defect — no migration
SQL changed):** the URL-less `social_community` opportunity initially passed
`source_platform = NULL`, violating the `NOT NULL` constraint; fixed by giving it
a platform name (URL-less is fine — `target_url` stays NULL). Re-ran clean.

**Still pending:** service wiring — Off-Page Authority + AI Visibility remain
mock-only in the UI until the Stage 6 services are wired (plan §13).

---

## 8. What remains (later phases)

- **Applied to TEST + structurally verified + smoke-tested PASS + UI-seeded.**
  Next: service-wire Off-Page Authority + AI Visibility (plan §13), then live-test.
- **No service wiring** (`seoOffPageAuthoritySupabaseService` /
  `seoAiVisibilitySupabaseService` + adapter — next phase, plan §13).
- **No production apply** — gated per `BACKEND_MILESTONE_HANDOFF.md` §5.

---

## 9. Test checklist (realized by the §7d smoke test — all PASS)

- Positive manager inserts on all 8 tables; junction integrity trigger rejects a
  cross-workspace link.
- Opportunity RPC: legal path (`shortlist→request_approval→start→complete`)
  updates status + writes activity; unsafe jump (`start` from `suggested`,
  reopening a terminal) raises; `reject` allowed only for owner/admin.
- Campaign RPC: `submit_for_approval→approve`; team_member `approve` raises
  (manager-only); owner/admin `approve` succeeds.
- RLS SELECT for owner/admin/team/client; non-member 0 rows (each in
  `BEGIN; SET LOCAL ROLE authenticated; … ROLLBACK`).
- Client is read-only: INSERT raises, UPDATE 0 rows, each transition RPC raises.
- Activity is append-only: UPDATE/DELETE blocked.
- CHECK rejections (each enum + `spam_risk_flags` element + activity exactly-one).
- Uniqueness: junction PK, task `(campaign_id, position)`, D7 active-only URL
  dup rejected — but a terminal (`avoided`) duplicate URL, a URL-less duplicate,
  and a **re-observed prompt on a later `observed_on`** are all allowed (D4/D7).
- Cascades: delete campaign → tasks/junction/campaign-activity gone; delete
  prompt → mentions gone.

---

## 10. Production warning

⚠️ **Do not apply to production.** Additive and non-destructive, but production
apply is gated (target-project confirmation, backup/branch strategy, final
migration review, technical-owner sign-off — `BACKEND_MILESTONE_HANDOFF.md` §5).
This SQL has only been authored; it has not touched any database.

---

## 11. Phase 15D — Atomic campaign-create RPC (migration `…120024`, added 2026-07-12)

Additive follow-up migration
`20260712120024_seo_stage6_authority_campaign_create_rpc.sql` — a 24th Stage 6
migration file that does **not** edit any already-applied migration. It adds one
guarded, atomic campaign-creation RPC, because campaign creation previously had
no RPC (the two migration-20 RPCs only transition existing rows) and the
frontend's original 3-request + client-side compensating-delete flow was not a
single transaction.

**RPC:** `public.seo_authority_campaign_create(p_website_id uuid, p_name text,
p_goal text, p_owner text, p_due_date date DEFAULT NULL, p_opportunity_ids
uuid[] DEFAULT '{}') RETURNS uuid`. `LANGUAGE plpgsql SECURITY DEFINER SET
search_path = public` — same security pattern as the migration-20 transition
RPCs. Inside one function body (one transaction) it: resolves
`workspace_id`/`website_url` server-side from `seo_websites` (client-supplied
values not accepted); enforces the `owner/admin/team_member` (or global admin)
role check (clients + non-members rejected); validates non-empty name/goal, the
`p_owner` enum, and that every opportunity belongs to the same
workspace+website; dedupes `p_opportunity_ids`; inserts the campaign
(`approval_status` omitted → column default `draft`, never `pending_approval`),
the junction rows, and one task per opportunity (`label = suggested_action`,
`is_complete=false`, deterministic 0-based `position`). Any failure raises →
the whole call rolls back → zero rows. `REVOKE ALL FROM PUBLIC` +
`REVOKE ALL FROM anon` + `GRANT EXECUTE TO authenticated` (stricter than the
migration-20 RPCs, which left anon's default grant). No new `activity_type` and
no activity row (creation is not a transition; D5a documents activity for
transitions only). `source` left at its `manual_seed` default (the CHECK has no
app-created value; adding one would edit an applied migration — deliberately
deferred).

**Applied to TEST (`Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm`), 2026-07-12:**
- **Dry-run:** `BEGIN;` + the migration + a signature check + `ROLLBACK;` via
  `supabase db query --linked` — created cleanly inside the txn, absent after
  rollback (nothing persisted).
- **Apply:** `supabase db push --linked --dry-run` showed only `…120024`
  pending; `supabase db push --linked --yes` applied just that migration.
- **Structural verification** (via `supabase db query --linked`): identity args
  match; `prosecdef=true`; `proconfig={search_path=public}`; `RETURNS uuid`;
  EXECUTE grantees = `authenticated`, `postgres`, `service_role` (anon absent
  after the explicit `REVOKE FROM anon`).
- **Verification script** `supabase/test/seo_stage6_authority_campaign_create_verification.sql`
  — **PASS, all 13 scenarios**: owner/admin/team_member each create a draft
  campaign; client rejected; non-member rejected; `approval_status='draft'`;
  correct junction rows; correct task rows (label = `suggested_action`, 0-based
  positions); cross-workspace opportunity rejected; invalid owner rejected;
  duplicate opportunity ids deduped (one junction + one task each); a **forced
  child-write failure left net-zero campaign/junction/task rows** (function
  atomicity, via a temporary BEFORE INSERT trigger on the tasks table); and full
  teardown (idempotent, self-cleaning, `a7000000-` prefix). The script uses NO
  explicit BEGIN/COMMIT/ROLLBACK (the `db query -f` runner wraps the whole file
  in one transaction), runs as `postgres` with per-test jwt switching, and
  DELETEs all its rows at the end.

**Production:** untouched. The migration + verification script targeted the
disposable TEST project only.

---

## 12. Phase 15E — Campaign-transition RPC verification (no migration change, added 2026-07-12)

**No backend object was created or altered.** This is a TEST-only verification
of the **existing** `seo_authority_campaign_transition` RPC (migration
`…120020`, applied and structurally verified back in Stage 6). New file:
`supabase/test/seo_stage6_authority_campaign_transition_verification.sql`.
Uses a fresh disposable prefix **`a8000000-`** (distinct from the smoke test's
`99999999-`, the UI seed's `a6000000-`, and the campaign-create verification's
`a7000000-`).

**Scenarios (all PASS on `Digi_SEO_Test`, 2026-07-12; idempotent re-run also
PASS):**
- **Legal transitions, per role + activity row.** `submit_for_approval`
  (draft→pending_approval) and `return_to_draft` (rejected→draft AND
  pending_approval→draft) succeed for owner/admin/team_member; `approve`
  (pending_approval→approved) and `reject` (pending_approval→rejected) succeed
  for owner/admin only. Each success writes exactly one `seo_authority_activity`
  row with `subject_type='campaign'`, `opportunity_id IS NULL`, matching
  `activity_type`/`from_status`/`to_status`, and the correct
  `actor_role_snapshot` (`owner`/`admin`/`team_member`).
- **Role rejections.** client + non-member rejected on every action;
  team_member additionally rejected on `approve`/`reject`. Each rejection
  leaves the campaign status unchanged and writes **no** activity row.
- **Illegal / unsupported transitions rejected** (as owner, so the status guard
  is what fires): submit-from-pending_approval, approve-from-draft,
  reject-from-draft, approve-from-rejected, reject-from-approved,
  return_to_draft-from-approved, submit-from-approved, approve-from-approved,
  an unknown action, and a missing/nonexistent campaign id.
- **Data integrity.** After a successful transition the campaign's
  `workspace_id`/`website_id`, its `seo_authority_campaign_opportunities`
  junction links, and its `seo_authority_campaign_tasks` (label + is_complete +
  order) are all unchanged, and exactly one activity row was appended.
- **Append-only activity (RLS-enforced).** A direct UPDATE and a direct DELETE
  of `seo_authority_activity`, attempted **as the `authenticated` role**
  (switched in-block so RLS is genuinely enforced), both affect **0 rows** —
  the table has no UPDATE/DELETE policy for anyone; the rows are then confirmed
  intact and untampered.
- **Cleanup.** Teardown deletes the disposable workspace (cascading away its
  website/opportunities/campaign/tasks/junctions/activity), drops the four
  `_seo8_*` helper functions, and asserts **zero** `a8000000-` rows remain
  across all affected Stage 6 tables. Verified clean after both runs.

**Execution model** matches the campaign-create verification: no explicit
BEGIN/COMMIT/ROLLBACK (single-transaction runner); runs as `postgres` with
per-test jwt switching for RPC authorization; each transition test forces the
campaign's from-status via a privileged setup helper so tests are
order-independent. No service-role key used.

**Production:** untouched. The verification script targeted the disposable TEST
project (`Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm`) only; no existing
migration, seed, RLS policy, or frontend code was changed.
