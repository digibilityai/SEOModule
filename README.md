# Digibility SEO Intelligence Module

Standalone Vite + React + TypeScript app for SEO Intelligence. Built to run
independently during development and plug into the main Digibility app later.
See `PROJECT_CONTEXT.md` and `CLAUDE.md` for full scope and rules.

## Stack

Vite, React 18, TypeScript, React Router, Supabase, TanStack React Query,
Tailwind CSS, shadcn/ui, Radix UI, lucide-react — same stack as the reference
app (`digibility-UI-Kit-small`).

## Setup

```bash
npm install
cp .env.example .env
# fill VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY with the SAME
# Supabase project used by the main Digibility app
npm run dev
```

App runs at `http://localhost:8090`.

## Project status (summary)

For the always-current, authoritative status, read **`CURRENT_PROJECT_STATUS.md`**;
for a map of every documentation file, read **`PROJECT_DOCUMENTATION_INDEX.md`**.
In brief, as of Phase 14B.2:

- **Backend (Supabase):** Stages 1–5 (access/workspaces/websites; audit/
  recommendations/approval; Content Studio; Page Performance Tracker; Decline
  Diagnosis Engine) are applied to a **TEST Supabase project and verified**
  (dry-run + structural checks + SQL smoke tests). **Production untouched.**
- **Frontend/service wiring:** complete through Phase 14B.2, all behind a
  mock/Supabase data-mode adapter — mock mode is the default and the fallback.
  Off-Page Authority, AI Visibility, Competitors, Roadmap, and Reports remain
  mock-only (no backend stage yet).
- **Test data:** base UI seed dataset + Stage 4 and Stage 5 UI seed extensions
  applied and verified on TEST (Stage 5: 8 diagnoses / 20 evidence / 6
  current-view rows).

## Data mode

The app runs in **mock mode by default**. To exercise the Supabase-wired
services against the TEST project, set `VITE_SEO_DATA_MODE=supabase` (with valid
`VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`) — see `SERVICE_LAYER_WIRING_PLAN.md`.
Invalid/missing config safely resolves back to mock.

## Not done yet (later work)

- No real crawler, GSC/GA4, LLM generation, or publishing — seeded/placeholder
  data only.
- No production apply (gated — see `BACKEND_MILESTONE_HANDOFF.md` §5).
- No backend for Off-Page Authority, AI Visibility, Competitors, Roadmap,
  Reports yet.
- Admin integration into the existing Digibility Admin Panel is future work.
- No data exchange with Visibility Management yet.
