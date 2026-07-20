# Digibility SEO Frontend — Cloud Run Deployment Readiness

**Status:** LOCAL READINESS ESTABLISHED. Container artifacts created and statically
verified. **No deployment occurred.** No Cloud Run service, Cloud Build trigger,
Artifact Registry repository, or any other Google Cloud resource was created,
modified, or contacted. Nothing was staged, committed, or pushed. No backend, worker,
Supabase, database, RPC, RLS, or migration file was touched. `MODULE_LOCKS.md` was not
modified.

## 1. Chosen container architecture

Multi-stage Docker build, per the task's preferred approach:

- **Build stage** — `node:20.18-alpine`, installs with `npm ci` against the repo's
  authoritative `package-lock.json`, runs the existing unmodified `npm run build`
  (`vite build`) script. Nothing from this stage ships in the final image.
- **Runtime stage** — `nginxinc/nginx-unprivileged:1.27-alpine`, the officially
  maintained non-root variant of the standard nginx image (already runs as a
  non-root user and listens on unprivileged ports like 8080 by default, without
  hand-rolled permission fixes). Serves only the compiled `dist/` output.

No general-purpose Node application server was added, and no new npm runtime
dependency was added to serve static files — nginx serves the build output directly,
per the task's stated preference.

## 2. Files added or changed

All new, all additive. No existing file was modified.

| File | Purpose |
|---|---|
| [Dockerfile](Dockerfile) | Multi-stage build + runtime image definition (repo root). |
| [.dockerignore](.dockerignore) | Build-context exclusions (repo root). |
| [docker/nginx.conf.template](docker/nginx.conf.template) | nginx server config template, `${PORT}`-substituted at container start. |
| [docker/security-headers.conf](docker/security-headers.conf) | Shared low-risk security-header snippet, `include`d by every location block. |
| This file | Readiness record. |

`crawler-worker/Dockerfile` and `crawler-worker/.dockerignore` (pre-existing, locked
scope) were read for convention reference only and were **not modified**.

## 3. Build process

```
FROM node:20.18-alpine AS build
WORKDIR /app
ARG VITE_SUPABASE_URL="" 
ARG VITE_SUPABASE_ANON_KEY=""
ARG VITE_SEO_DATA_MODE="mock"
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL VITE_SUPABASE_ANON_KEY=$VITE_SUPABASE_ANON_KEY VITE_SEO_DATA_MODE=$VITE_SEO_DATA_MODE
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build
```

- `package.json` + `package-lock.json` are copied and installed **before** the rest
  of the source, so the dependency layer is cached until the lockfile changes.
- `npm ci` is used (not `npm install`) because `package-lock.json` is the repo's
  authoritative lockfile.
- `COPY . .` relies on `.dockerignore` (§ below) to keep `node_modules`, `dist`,
  `crawler-worker/`, `supabase/`, every local `.env*` file, and ~80 root-level
  documentation `.md` files out of the build context — this is deliberately not an
  enumerated file list, so a future new config file (another `tsconfig.*.json`, a
  `postcss`/`tailwind` change, etc.) does not silently break the image build the way
  a hand-maintained `COPY` allowlist could.
- The build command itself, `npm run build`, is **unmodified** — no new script was
  added to `package.json`.
- A failed `npm ci` or `npm run build` fails the `docker build` (no `|| true`,
  no swallowed exit code).

## 4. Runtime server

`nginxinc/nginx-unprivileged:1.27-alpine`. Two files are copied into the image:

- `docker/nginx.conf.template` → `/etc/nginx/templates/default.conf.template`
  (picked up automatically by the base image's own entrypoint scripts).
- `docker/security-headers.conf` → `/etc/nginx/snippets/security-headers.conf`
  (an `include`d snippet, not auto-loaded — referenced explicitly by every location
  block, since nginx's `add_header` does not inherit into a child block that itself
  sets `add_header`).
- The compiled frontend: `dist/` → `/usr/share/nginx/html`.

No `USER` directive was added — the base image already runs nginx as its own
built-in non-root user by default; this was verified by reading the base image's
public Dockerfile/documentation rather than assumed.

## 5. `$PORT` handling

- `ENV PORT=8080` in the Dockerfile is the **safe local/default value**, used when
  the container is run standalone (e.g. local `docker run` without `-e PORT=...`).
- At container **start**, the base image's own entrypoint script runs `envsubst`
  over `docker/nginx.conf.template`, replacing `${PORT}` with whatever `PORT` value
  is actually present in the container's environment at that moment — which is the
  value **Cloud Run injects at runtime**, not a value baked in at image-build time.
- The generated server listens on `listen 0.0.0.0:${PORT} default_server;` —
  **`0.0.0.0`, never `127.0.0.1`**, and never hardcoded to `80`.
- The substitution is scoped to real OS environment variables only (the base
  image's entrypoint script computes the substitution list from `env`), so nginx's
  own runtime variables used elsewhere in the template — `$uri` (no braces) — are
  never touched. Confirmed by inspecting the template: the only `${...}`-bracketed
  token anywhere in the file is `${PORT}`; every other variable reference uses the
  plain `$name` form that `envsubst`'s restricted substitution list does not match.
  See the file's own header comment for this reasoning in context.
- If `envsubst` or the generated config is invalid, nginx fails to start and the
  container exits non-zero — there is no wrapper shell that could hide that failure
  (the Dockerfile does not override the base image's `ENTRYPOINT`, and its `CMD` is
  the plain, foreground `["nginx", "-g", "daemon off;"]`).

## 6. SPA fallback behaviour

`location /` (the catch-all, lowest-precedence prefix block) uses
`try_files $uri $uri/ /index.html;`. For any request that is not a real file under
`/assets/` and does not end in a recognized static-asset extension (§7), nginx falls
back to serving `/index.html` with HTTP 200 — letting `react-router-dom`
(`BrowserRouter`, `base: "/"`, confirmed via `vite.config.ts` and `src/App.tsx`)
resolve the route entirely client-side, exactly as it already does in `npm run dev`/
`vite preview`. A query string (e.g. `/help/search?q=verify`) does not affect this —
nginx strips it before computing `$uri`. Verified (by logic trace against the real
`dist/` output — see §11) for:

- `/`, `/help`, `/help/search?q=verify`,
  `/help/category/reports-decline-diagnosis`,
  `/help/article/investigating-traffic-ranking-decline`, `/seo/login`,
  `/seo/dashboard`.

No route-specific server logic exists — this server has no knowledge of
authentication, roles, or which paths are protected. All of that continues to live
entirely inside the already-built React app (`ProtectedRoute`, `useSeoAccess`,
`AuthProvider`, the public `/help*` routes) and is completely unchanged by this
container.

## 7. Missing-asset 404 behaviour

Three ordered location blocks (nginx precedence: exact match → `^~`-prefixed match
→ regex match → plain prefix match) keep real/missing assets from ever falling
through to the SPA shell:

1. `location ^~ /assets/` — `try_files $uri =404;`. Any path under `/assets/`
   (Vite's content-hashed build output) that doesn't exist on disk is a real 404.
   The `^~` modifier stops nginx from also evaluating the regex block below for
   anything under `/assets/`.
2. `location ~* \.(?:js|mjs|css|map|json|webmanifest|txt|xml|ico|png|jpe?g|gif|webp|avif|svg|woff2?|ttf|otf|eot)$`
   — `try_files $uri =404;`. Any other asset-shaped path (by extension), anywhere
   else in the tree, that doesn't exist is also a real 404 — this is a safety net
   for future static files (e.g. a `public/favicon.ico`) even though none ship in
   today's `dist/` output.
3. The catch-all `location /` is only ever reached for extensionless paths (or a
   path under neither of the above), so a missing asset can never reach the SPA
   fallback.

Verified by logic trace: `/assets/missing.js`, `/missing-image.png`, and
`/missing-font.woff2` all classify as 404, never as `index.html`. The 404 body is
nginx's own built-in default error page (no custom `error_page` was added — kept to
the smallest reliable config per the task's instruction); the important, verified
property is the **status code**, not the page's content.

## 8. Cache policy

| Path pattern | Cache-Control | Rationale |
|---|---|---|
| `/index.html` (exact, and via SPA fallback) | `no-cache` | The shell must always revalidate so a new deploy's hashed asset references become visible immediately — never served stale for up to some TTL. |
| `/assets/*` (content-hashed Vite output) | `public, max-age=31536000, immutable` | The filename itself changes whenever the content does; safe to cache for a year. |
| Any other static asset (by extension) | `public, max-age=3600` | Moderate caching for non-hashed static files, matching the task's "sensible moderate caching" guidance. |

No aggressive caching was applied anywhere that could risk a stale application
shell — `index.html` itself is `no-cache` in every code path that can serve it.

## 9. Security headers

Applied via `docker/security-headers.conf`, `include`d into every location block
(so they are present on both 200 and 404 responses, via the `always` flag):

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `X-Frame-Options: SAMEORIGIN`
- `Permissions-Policy: camera=(), microphone=(), geolocation=(), interest-cohort=()`

**Deliberately not added**, per the task's explicit instruction:

- **Content-Security-Policy** — the repository has no existing CSP; adding one here
  risks silently breaking Supabase/auth/runtime requests and needs its own separate
  review.
- **Strict-Transport-Security** — Cloud Run terminates TLS upstream of this
  container; HSTS is an edge/domain-level decision that does not belong in the
  container config.

## 10. Local build/run commands

Docker is not installed in the environment this readiness work was performed in
(confirmed: `docker --version` → command not found). The commands below were
**authored and statically reviewed, not executed**. They are exactly what an
operator (or CI) with Docker available should run:

```bash
# From the repository root.

# 1. Build the image (default mock mode — no Supabase build args supplied).
docker build -t digibility-seo-frontend:local .

# 2. Run it locally with Cloud Run's default port.
docker run --rm -p 8080:8080 -e PORT=8080 digibility-seo-frontend:local

# 3. In another terminal, verify routes (see §11 for the full expected table).
curl -i http://localhost:8080/
curl -i http://localhost:8080/help
curl -i "http://localhost:8080/help/search?q=verify"
curl -i http://localhost:8080/help/category/reports-decline-diagnosis
curl -i http://localhost:8080/help/article/investigating-traffic-ranking-decline
curl -i http://localhost:8080/seo/login
curl -i http://localhost:8080/assets/index-JigMp1wz.js   # exact hashed filename — see 4.
curl -i http://localhost:8080/assets/index-COVmcwW1.css  # exact hashed filename — see 4.
curl -i http://localhost:8080/assets/missing.js
curl -i http://localhost:8080/missing-image.png

# 4. The hashed asset filenames above change on every build. Get the current
#    ones from the built dist/ output (or `docker run --rm digibility-seo-frontend:local ls /usr/share/nginx/html/assets`):
ls dist/assets/

# 5. Optional: build with real Supabase config (still does not deploy or
#    contact anything — only affects what gets baked into the JS bundle).
docker build \
  --build-arg VITE_SEO_DATA_MODE=supabase \
  --build-arg VITE_SUPABASE_URL="<test-project-url>" \
  --build-arg VITE_SUPABASE_ANON_KEY="<test-project-anon-key>" \
  -t digibility-seo-frontend:local-supabase .
```

## 11. Local verification results

| Check | Result |
|---|---|
| `npx tsc --noEmit -p tsconfig.app.json` | **PASS** (0 errors) — executed. |
| `npm run build` | **PASS** — executed; `dist/index.html`, `dist/assets/index-JigMp1wz.js`, `dist/assets/index-COVmcwW1.css` produced (same pre-existing chunk-size advisory as prior slices, unrelated). |
| `docker build` | **NOT PERFORMED** — Docker is not installed in this environment. Commands documented in §10 for the operator to run. |
| Container start / HTTP verification | **NOT PERFORMED** for the same reason. |
| nginx routing-logic trace | **PASS (static trace, not a running container)** — a small local script re-implemented the exact `location` precedence and `try_files` semantics from `docker/nginx.conf.template` and ran it against the real `dist/` file listing for every required path. All 12 required paths classified correctly: application routes → `200`, SPA-fallback shell, `no-cache`; the two real hashed assets → `200`, immutable long-lived cache; the three missing-asset paths → `404`. This is a logic-correctness check, **not proof the container runs** — it does not exercise nginx, `envsubst`, or the base image at all. |
| `${PORT}`-only substitution check | **PASS** — grepped the template; the only `${...}`-braced token anywhere in the file is `${PORT}`; `$uri` (used in every `try_files`) uses the plain, non-braced form untouched by the base image's restricted `envsubst` variable list. |

**No claim is made that the container builds, starts, or serves traffic correctly
end-to-end** — that requires the Docker build+run steps in §10, which were not
available to run here.

## 12. Required Cloud Run service settings (undecided inputs — not fabricated)

The following are genuine business/operational decisions this slice does not make
and does not guess at:

- **Service type:** Cloud Run **service** (not a Job) — this container serves
  continuous HTTP traffic.
- **Container port:** supplied through `PORT` (already handled — §5); Cloud Run's
  default is 8080, which matches this image's own default.
- **Ingress (public vs. authenticated-only):** a separate business/security
  decision. Note: the public `/help*` routes are designed to be reachable
  signed-out; the `/seo/*` routes are protected **inside the React app itself**
  (`ProtectedRoute`), not by this container or by Cloud Run ingress — ingress
  controls whether the container is reachable at all, not which in-app routes
  require login.
- **Min/max instances, concurrency:** an operational decision; not set here.
- **CPU/memory allocation:** an operational decision; not set here. This is a
  static file server — the base image and build output are both lightweight — but
  the exact allocation is still an operator choice.
- **Region:** an operational decision; not set here.
- **Custom domain:** a later configuration step, unrelated to this container.
- **Project ID, service name, Artifact Registry repository:** not fabricated —
  none exist yet in any file this task touched.

## 13. Environment-variable strategy

This is the most important non-obvious point for whoever deploys this image:

- **Vite bakes `VITE_*` variables into the static JS bundle at BUILD time.**
  Cloud Run's runtime environment-variable injection (the `-e`/console "Variables &
  Secrets" mechanism) has **no effect** on an already-built static SPA — those
  variables are for server-side/runtime code, and this image serves pre-compiled,
  static files. Setting `VITE_SUPABASE_URL` as a Cloud Run runtime env var would be
  silently ineffective.
- **Default behaviour (this slice's own local verification and the readiness
  target):** no Supabase build args are supplied, so `VITE_SEO_DATA_MODE` defaults
  to `mock` and the app runs in the same safe, no-network mock mode it already uses
  in local dev when Supabase config is absent (`src/config/runtimeConfig.ts` never
  throws on missing config). This is exactly what was verified in §11 — no Supabase
  or backend availability is required to build or serve this image.
- **If a real Supabase-backed deployment is later wanted:** the **public** Supabase
  URL and anon key (never a service-role key — this rule already exists in
  `.env.example` and is unchanged here) must be supplied as **Docker build
  arguments** (`--build-arg`, or the equivalent Cloud Build substitution) at image-
  build time, not as Cloud Run runtime variables. A new image must be built for any
  change to these values or to `VITE_SEO_DATA_MODE`.
- Secrets in the broader sense (a future server-side secret, if this architecture
  ever grows one) must be supplied through Cloud Run's own configuration — never
  baked into the image. This image today has no server-side secret at all: nginx
  serves static files only.

## 14. Rollback

Deleting the four new files ([Dockerfile](Dockerfile), [.dockerignore](.dockerignore),
[docker/nginx.conf.template](docker/nginx.conf.template),
[docker/security-headers.conf](docker/security-headers.conf)) fully reverts this
slice — no existing file was modified, no database/migration/backend/worker change
exists to roll back, and no Cloud Run service was ever created.

## 15. Known limitations

- **No actual container build/run/HTTP verification was performed** — Docker is
  unavailable in this environment. §10 documents the exact commands; §11 is explicit
  about what was and was not verified.
- **No deployment target decision has been made** (region, service name, project,
  ingress policy, scaling, CPU/memory) — §12 lists these as genuinely open, not
  guessed.
- **The 500 kB+ single JS chunk size warning from `vite build`** (pre-existing,
  unrelated to this slice) means the initial `/assets/index-*.js` download is
  larger than ideal; this is a frontend build-optimization concern, out of scope
  for container readiness, and was not touched.
- **No `public/` directory exists in this repo today** (no favicon, robots.txt, or
  manifest) — the "any other asset-like path" nginx location (§7) is a forward-
  looking safety net, not something exercised by the current build output.
- **This image has never been pushed to any registry** — Artifact Registry/Container
  Registry setup is a Cloud Run deployment step, not part of this slice.

## 16. Exact deployment checklist (for the operator, later — not performed here)

1. Confirm Docker is available; run the commands in §10 and confirm all expected
   results in the table under §11's route-verification intent (status codes,
   content types, SPA shell content, no `index.html` for missing assets).
2. Decide and record the genuinely-open inputs in §12 (project, region, service
   name, ingress, scaling, CPU/memory).
3. Decide, per §13, whether this deployment should run in `mock` mode (no Supabase
   build args — the default) or be built with real public Supabase config.
4. Build and push the image to Artifact Registry (`gcloud builds submit` or
   `docker push`) — not performed here.
5. Deploy with `gcloud run deploy` (or the Cloud Run console / Terraform), supplying
   only the settings decided in step 2 — not performed here.
6. Re-run the route/asset verification in §11 against the live Cloud Run URL.
7. Only after that passes, consider a custom domain and any ingress-policy change.

## 17. Confirmation that no deployment occurred

No `gcloud` command was run. No Google Cloud resource (Cloud Run service, Cloud
Build trigger, Artifact Registry repository, or any other) was created, modified,
inspected, or contacted. No image was built (Docker unavailable) or pushed. No TEST
or production Supabase project was contacted. Nothing in this repository was staged,
committed, or pushed.
