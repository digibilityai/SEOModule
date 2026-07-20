# Fresh SEO Supabase TEST project — setup from scratch

Use this when standing up a **new** dedicated SEO Supabase project for GCP TEST
(not Digibility Core, not production). Digibility Core remains the only
customer login; this project holds SEO data + SEO Auth sessions.

## 1. Create the project (Supabase Dashboard)

1. Open [https://supabase.com/dashboard](https://supabase.com/dashboard)
2. **New project**
   - Name suggestion: `Digi_SEO_GCP_Test` (or similar — not production)
   - Database password: store in your password manager
   - Region: prefer the same region family as Digibility TEST if possible
3. Wait until the project is healthy
4. Copy and save (Project Settings → API):
   - **Project URL** → `https://<ref>.supabase.co`
   - **anon / publishable** key
   - **service_role** key (server only — never in `VITE_*` or frontend)
5. Copy **Project ref** from the URL (`https://supabase.com/dashboard/project/<ref>`)

## 2. Auth settings (required for SSO bridge)

In the **SEO** project → **Authentication → URL configuration**:

| Setting | Value |
|---------|--------|
| Site URL | `http://localhost:8090` for local; later add your SEO Cloud Run / `seo-test.digibility.ai` |
| Redirect URLs | `http://localhost:8090/**`, and later `https://<seo-cloud-run-url>/**` |

In **Authentication → Providers**:

- Keep **Email** enabled (the bridge uses Admin `generateLink` magiclink → `verifyOtp`; no customer password signup on SEO).
- You do **not** need Google OAuth on the SEO project (login is Digibility-only).

Disable or ignore public signup on SEO if your dashboard exposes it — customers must not create SEO-only accounts when bridge config is on.

## 3. Apply all migrations (order matters)

Apply **every** file under `supabase/migrations/` in filename order.
Last file must be the SSO bridge:

`20260720121000_seo_cross_project_identity_bridge.sql`

### Option A — Supabase CLI (preferred for 39 files)

From the SEO repo, after Cloud SDK / Node are available:

```powershell
cd C:\Users\rst_r\gitprojects\digibility\SEO\SEOModule

npx supabase login
npx supabase link --project-ref <YOUR_NEW_SEO_PROJECT_REF>

# Review then push (applies all pending migrations in order)
npx supabase db push
```

If prompted, confirm this is the **new TEST** project (never production).

### Option B — SQL Editor (manual)

Open **SQL Editor → New query**. Paste and **Run** each file below **one at a time**, top to bottom. Stop if any file errors.

1. `20260711120001_seo_stage1_access_module.sql`
2. `20260711120002_seo_stage1_workspaces.sql`
3. `20260711120003_seo_stage1_websites.sql`
4. `20260711120004_seo_stage2_audit.sql`
5. `20260711120005_seo_stage2_recommendations.sql`
6. `20260711120006_seo_stage2_approval.sql`
7. `20260711120007_seo_stage3_content_plan.sql`
8. `20260711120008_seo_stage3_content_drafts.sql`
9. `20260711120009_seo_stage3_content_assets.sql`
10. `20260711120010_seo_stage4_page_inventory.sql`
11. `20260711120011_seo_stage4_page_keywords.sql`
12. `20260711120012_seo_stage4_performance_snapshots.sql`
13. `20260711120013_seo_stage4_performance_latest_view.sql`
14. `20260711120014_seo_stage5_decline_diagnoses.sql`
15. `20260711120015_seo_stage5_decline_diagnosis_evidence.sql`
16. `20260711120016_seo_stage5_decline_diagnosis_current_view.sql`
17. `20260711120017_seo_stage6_authority_opportunities.sql`
18. `20260711120018_seo_stage6_authority_campaigns.sql`
19. `20260711120019_seo_stage6_authority_campaign_children.sql`
20. `20260711120020_seo_stage6_authority_activity.sql`
21. `20260711120021_seo_stage6_ai_prompt_tracking.sql`
22. `20260711120022_seo_stage6_ai_content_gaps.sql`
23. `20260711120023_seo_stage6_ai_mentions.sql`
24. `20260712120024_seo_stage6_authority_campaign_create_rpc.sql`
25. `20260713120025_seo_phase16c_crawl_control_plane.sql`
26. `20260714120026_seo_phase16d_worker_lifecycle.sql`
27. `20260714120027_seo_phase16e_crawl_discovery.sql`
28. `20260714120028_seo_phase16f_crawl_extraction.sql`
29. `20260714120029_seo_phase16g_publishing.sql`
30. `20260715120030_seo_crawl_audit_finalization.sql`
31. `20260716120031_seo_p1a_step1_ownership_verification.sql`
32. `20260716120032_seo_p1a_step2a_ownership_verification_rpcs.sql`
33. `20260716120033_seo_p1a_step2b_ownership_verification_service_rpcs.sql`
34. `20260719120034_seo_p1b_verified_only_crawl_enqueue.sql`
35. `20260720120035_seo_reports_foundation.sql`
36. `20260720120036_seo_report_generate.sql`
37. `20260720120037_seo_report_generate_revoke_anon.sql`
38. `20260720120038_seo_report_export_data.sql`
39. `20260720121000_seo_cross_project_identity_bridge.sql` ← SSO identity mirror

## 4. Quick structural check

In SQL Editor:

```sql
select to_regclass('public.user_module_access') as user_module_access,
       to_regclass('public.seo_workspaces') as seo_workspaces,
       to_regclass('public.seo_identity_profiles') as seo_identity_profiles;

select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('has_seo_module_access', 'seo_is_global_admin', 'set_updated_at')
order by 1;
```

Expect non-null table names and those three functions present.

## 5. Wire local SEO `.env` to the new project

Update `SEOModule/.env` (gitignored):

```env
VITE_SUPABASE_URL=https://<NEW_SEO_REF>.supabase.co
VITE_SUPABASE_ANON_KEY=<new-seo-anon-key>
VITE_SEO_DATA_MODE=supabase

VITE_DIGIBILITY_APP_URL=http://localhost:8080
VITE_DIGIBILITY_BRIDGE_URL=https://dwkfhnbcvaljvrcsxzkl.supabase.co/functions/v1/seo-bridge
VITE_DIGIBILITY_ANON_KEY=<digibility-core-anon-key>
```

Restart `npm run dev` on `:8090`.

## 6. What Digibility Core still needs (separate project)

The new SEO project does **not** replace Digibility Core. Still required on Core:

- Entitlement migrations + `seo-bridge` Edge Function
- Secrets pointing at **this** new SEO URL + service_role key:
  - `SEO_SUPABASE_URL`
  - `SEO_SUPABASE_SERVICE_ROLE_KEY`
  - `SEO_APP_ORIGIN` / `DIGIBILITY_APP_ORIGIN`

## 7. Hand off values for GCP later

Keep these for Secret Manager / Cloud Run:

| Secret / env | Source |
|--------------|--------|
| `seo-test-supabase-url` | New project URL |
| `seo-test-supabase-anon-key` | New project anon key |
| Edge `SEO_SUPABASE_SERVICE_ROLE_KEY` | New project service_role |
| `seo-test-digibility-anon-key` | Digibility Core anon key |

## Do not

- Put service_role in any frontend / `VITE_` variable
- Apply these migrations to Digibility Core
- Point production Digibility at this TEST project
- Reuse Digi_SEO_Test credentials if you intentionally want a clean GCP TEST stack
