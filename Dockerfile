# syntax=docker/dockerfile:1.7
#
# Digibility SEO frontend — Cloud Run container.
#
# Multi-stage build: compile the existing Vite/React SPA, then serve the
# static output with a minimal, non-root nginx. Nothing backend/worker/
# database/Supabase-related is built or run in this image — this serves
# ONLY the already-independent frontend (see PROJECT_CONTEXT.md / CLAUDE.md:
# SEO is developed as a separate module from the existing Digibility app,
# and this image ships the SEO frontend build only).
#
# NOT deployed by this file or by any command run alongside it — building
# this image locally does not contact Cloud Run, Cloud Build, TEST, or
# production.

# ---------------------------------------------------------------------------
# Stage 1: build — installs with the repo's exact lockfile and runs the
# existing production build script. Nothing from this stage ships in the
# final image; only its /app/dist output is copied into stage 2.
# ---------------------------------------------------------------------------
FROM node:20.18-alpine AS build
WORKDIR /app

# Optional build-time frontend config. Empty/default values keep the app in
# its existing safe "mock" data mode (src/config/runtimeConfig.ts) and
# require no Supabase contact to build or serve — this is the default used
# by every command in this repository's own readiness documentation. Vite
# bakes VITE_* values into the static bundle at BUILD time; Cloud Run's
# runtime environment variables do NOT reach an already-built SPA bundle
# (see docker/nginx.conf.template's header comment and the readiness doc,
# section 13, for the full explanation). Only the PUBLIC Supabase URL and
# anon key may ever be supplied here — never a service-role key, per the
# existing rule in .env.example.
ARG VITE_SUPABASE_URL=""
ARG VITE_SUPABASE_ANON_KEY=""
ARG VITE_SEO_DATA_MODE="mock"
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL \
    VITE_SUPABASE_ANON_KEY=$VITE_SUPABASE_ANON_KEY \
    VITE_SEO_DATA_MODE=$VITE_SEO_DATA_MODE

# Install first, from the lockfile only, so this layer is cached until
# package.json/package-lock.json actually change.
COPY package.json package-lock.json ./
RUN npm ci

# Bring in the rest of the frontend source. .dockerignore excludes
# node_modules, dist, repository documentation, crawler-worker/, supabase/,
# and every local env file, so this does not pull backend/worker code,
# secrets, or unrelated large docs into the build context.
COPY . .

# The existing, unmodified production build command. A failed build fails
# this image build (no `|| true`, no swallowed exit code).
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2: runtime — static file serving only. No source code, no dev
# dependencies, no repository documentation, no .env files, no credentials.
# ---------------------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

# Config template (envsubst'd for ${PORT} at container start) and the
# shared security-header snippet it includes.
COPY docker/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY docker/security-headers.conf /etc/nginx/snippets/security-headers.conf

# The compiled frontend only.
COPY --from=build /app/dist /usr/share/nginx/html

# nginxinc/nginx-unprivileged already runs as its built-in non-root user;
# no additional USER directive is needed or added here.

# Cloud Run injects PORT at container start; 8080 is the safe local/default
# value (this base image's own unprivileged default), used when PORT is
# unset — e.g. `docker run -p 8080:8080 <image>`.
ENV PORT=8080
EXPOSE 8080

# Foreground as PID 1 via the base image's own entrypoint (not overridden
# here), so Cloud Run's SIGTERM on scale-down/redeploy reaches nginx
# directly — no shell wrapper that could swallow a startup failure or delay
# shutdown.
CMD ["nginx", "-g", "daemon off;"]
