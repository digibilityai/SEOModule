# GCP TEST deploy — Digibility ↔ SEO SSO

**Status:** scaffolding ready in source. Nothing is live until you run the
operator steps below against GCP + Supabase.

**Hosts used by Digibility today:** `testapp.digibility.ai` / `app.digibility.ai`
(not `.com`). This runbook uses `.ai` for TEST.

## What gets deployed

| Piece | Where | Repo artifact |
|-------|--------|----------------|
| Digibility UI | Cloud Run `digi-frontend-test` | UI `Dockerfile` + `cloudbuild.yaml` |
| SEO UI | Cloud Run `digi-seo-frontend-test` (new) | SEO `Dockerfile` + `cloudbuild.yaml` |
| `seo-bridge` | Digibility **Core** Supabase Edge Function | UI `supabase/functions/seo-bridge` |
| Entitlements | Digibility Core DB migrations | UI `supabase/migrations/2026072012*` |
| SEO identity | SEO Supabase DB migration | SEO `supabase/migrations/20260720121000_*` |

Crawler worker is **out of scope** for this cut.

## Order (do not skip)

### A. Supabase (before Cloud Run)

1. **SEO TEST project** (e.g. Digi_SEO_Test `snyzotgwwfomgafrsvfm`):
   - Apply all existing SEO migrations in order.
   - Apply `20260720121000_seo_cross_project_identity_bridge.sql` (SQL Editor or CLI).
2. **Digibility Core / DevApp** (`dwkfhnbcvaljvrcsxzkl` or your TEST Core):
   - Apply `20260720120000_module_entitlements_seo_bridge.sql`.
   - Apply `20260720122000_seo_grant_all_users.sql`.
3. **Deploy Edge Function** on Digibility Core (Dashboard or CLI):
   - Function name: `seo-bridge`
   - Code: `digibility-UI-Kit-small/supabase/functions/seo-bridge/index.ts`
   - **Verify JWT = OFF**
   - Secrets:
     ```text
     DIGIBILITY_APP_ORIGIN=https://testapp.digibility.ai,http://localhost:8080
     SEO_APP_ORIGIN=<SEO_CLOUD_RUN_OR_CUSTOM_URL>,http://localhost:8090
     SEO_SUPABASE_URL=https://<seo-test-ref>.supabase.co
     SEO_SUPABASE_SERVICE_ROLE_KEY=<seo-test-service-role>
     ```
   - After first SEO Cloud Run deploy, set `SEO_APP_ORIGIN` to that HTTPS origin
     (comma-keep localhost only on DevApp, never on production).

### B. GCP secrets + Artifact Registry

In GCP project `digibility-frontend` (or the project you use for frontends),
region `asia-southeast1`:

```bash
# Artifact Registry (once)
gcloud artifacts repositories create digi-seo-frontend-repo \
  --repository-format=docker \
  --location=asia-southeast1 \
  --description="Digibility SEO frontend"

# Secrets (once) — paste values when prompted / from files
echo -n "https://<seo-test-ref>.supabase.co" | gcloud secrets create seo-test-supabase-url --data-file=-
echo -n "<seo-anon-key>" | gcloud secrets create seo-test-supabase-anon-key --data-file=-
echo -n "<digibility-core-anon-key>" | gcloud secrets create seo-test-digibility-anon-key --data-file=-

# Grant the Cloud Run runtime SA access (same pattern as digi-frontend-test)
gcloud secrets add-iam-policy-binding seo-test-supabase-url \
  --member="serviceAccount:digi-frontend-runner@digibility-frontend.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
# repeat for seo-test-supabase-anon-key and seo-test-digibility-anon-key
```

### C. Deploy SEO Cloud Run (TEST)

From SEO repo root:

```bash
cd C:\Users\rst_r\gitprojects\digibility\SEO\SEOModule

# Manual one-shot (or create a Cloud Build trigger on cloudbuild.yaml)
gcloud builds submit --config=cloudbuild.yaml --project=digibility-frontend
```

After deploy, capture the service URL:

```bash
gcloud run services describe digi-seo-frontend-test \
  --region=asia-southeast1 --project=digibility-frontend \
  --format='value(status.url)'
```

Optional custom domain: map `seo-test.digibility.ai` → this service in Cloud Run
domain mappings / Load Balancer.

Update Edge Function secret `SEO_APP_ORIGIN` to include that HTTPS origin.

Update SEO Cloud Build substitution `_DIGIBILITY_APP_URL` if needed (default
`https://testapp.digibility.ai`).

### D. Redeploy Digibility TEST with `SEO_APP_URL`

1. Set Cloud Build substitution `_SEO_APP_URL` in UI `cloudbuild.yaml` (or trigger)
   to the SEO Cloud Run / custom URL from step C.
2. Rebuild/redeploy `digi-frontend-test` so `entrypoint.sh` injects `SEO_APP_URL`
   into `runtime-config.js` (required for linked logout cascade).

```bash
cd C:\Users\rst_r\gitprojects\digibility\UI\digibility-UI-Kit-small
gcloud builds submit --config=cloudbuild.yaml --project=digibility-frontend \
  --substitutions=_SEO_APP_URL=https://YOUR-SEO-TEST-URL
```

### E. Acceptance (TEST)

1. Open `https://testapp.digibility.ai` → sign in.
2. Header **SEO** → lands on SEO Cloud Run `/seo/auth/bridge` → dashboard.
3. Hard refresh SEO → still signed in.
4. Digibility **Log out** → both apps require login.
5. SEO **Sign out** → Digibility also logged out; no auto-relaunch.
6. SEO **Visibility** → Digibility still signed in (app switch).

## Production later

Repeat with:

- `app.digibility.ai` + `seo.digibility.ai` (or `.com` if DNS is ready)
- Production SEO Supabase project + Core production project
- Separate Cloud Run services / secrets (never reuse TEST service-role keys)
- Edge Function origins **without** localhost

## Local vs GCP

| Concern | Local | GCP TEST |
|---------|-------|----------|
| Digibility UI | `:8080` | `testapp.digibility.ai` |
| SEO UI | `:8090` | `digi-seo-frontend-test` / `seo-test.digibility.ai` |
| Bridge | deployed DevApp function or `functions serve` | DevApp `seo-bridge` |
| Config | `.env` / `VITE_*` | Cloud Run env + Secret Manager → `runtime-config.js` |
