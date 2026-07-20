# Digibility SEO Intelligence Module

Standalone Vite + React + TypeScript app for SEO Intelligence. Built to run
independently during development and plug into the main Digibility app later.

## Documentation (start here)

**Browse offline (no server):** open [`docs/index.html`](docs/index.html) in any browser.

That HTML guide covers overall architecture, request sequences, data-flow
sequences, modules/routes, tables/RPCs, crawler pipeline, ownership
verification, auth, and the service layer.

All project markdown files are consolidated in [`docs/markdown/`](docs/markdown/)
(62 files). Root stubs (`PROJECT_BOOTSTRAP.md`, `CURRENT_PROJECT_STATUS.md`, …)
point to those locations. See also [`docs/README.md`](docs/README.md).

| Doc | Purpose |
| --- | --- |
| [`docs/index.html`](docs/index.html) | Browseable architecture & flow docs |
| [`docs/markdown/PROJECT_BOOTSTRAP.md`](docs/markdown/PROJECT_BOOTSTRAP.md) | AI/session entry point |
| [`docs/markdown/CURRENT_PROJECT_STATUS.md`](docs/markdown/CURRENT_PROJECT_STATUS.md) | Authoritative status |
| [`docs/markdown/PROJECT_CONTEXT.md`](docs/markdown/PROJECT_CONTEXT.md) | Product scope & business rules |
| [`CLAUDE.md`](CLAUDE.md) | Coding-agent build rules |

## Stack

Vite, React 18, TypeScript, React Router, Supabase, TanStack React Query,
Tailwind CSS, shadcn/ui, Radix UI, lucide-react — same stack as the reference
app (`digibility-UI-Kit-small`).

## Setup

```bash
npm install
cp .env.example .env
# fill VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY for the dedicated SEO
# Supabase project; see .env.example for optional Digibility SSO bridge config
npm run dev
```

App runs at `http://localhost:8090`.

## Project status (summary)

For the always-current checkpoint, read
[`docs/markdown/CURRENT_PROJECT_STATUS.md`](docs/markdown/CURRENT_PROJECT_STATUS.md)
or the HTML [status page](docs/pages/status.html).

In brief:

- **Backend (Supabase):** Stages 1–6 + crawler (16C–16H) + ownership (P1a)
  applied to disposable **TEST** project only. **Production untouched.**
- **Frontend wiring:** Stages 1–6 reads; opportunity + campaign writes;
  crawl UI on `/seo/audit`; ownership UI on `/seo/websites`.
- **Cross-project SSO:** implemented in source (Digibility login + entitlement
  bridge to a dedicated SEO Supabase project); not deployed/live-tested.
- **Still mock-only / deferred:** Competitors, Roadmap, Reports; AI Visibility
  writes; GSC/GA4; production crawler deployment; P1b verified-only crawl gate.

## Data mode

The app runs in **mock mode by default**. To exercise Supabase-wired services
against TEST, set `VITE_SEO_DATA_MODE=supabase` (with valid
`VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`) — see
[`docs/markdown/SERVICE_LAYER_WIRING_PLAN.md`](docs/markdown/SERVICE_LAYER_WIRING_PLAN.md).
Invalid/missing config safely resolves back to mock.

## Architecture (one line)

Browser → service adapter (mock/Supabase) → Supabase PostgREST + RLS / guarded
RPCs → Postgres. Optional `crawler-worker/` (service_role) claims crawl jobs
and DNS ownership checks. **No customer-facing BFF.**
