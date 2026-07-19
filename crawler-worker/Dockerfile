# Minimal, production-shaped container for the crawler worker (NOT deployed here).
# No browser/crawling deps yet (Phase 1C). No secrets baked in — config is env-driven.
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev

FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
# tsx runtime for TS execution without a separate build step.
COPY --from=deps /app/node_modules ./node_modules
RUN npm install --no-save tsx@^4.19.2 typescript@^5.6.0
COPY package.json tsconfig.json ./
COPY src ./src
# Non-root runtime user.
USER node
# Config-check as a readiness/health command.
HEALTHCHECK --interval=30s --timeout=10s CMD ["node","--import","tsx","src/index.ts","--mode=dry-run"]
ENTRYPOINT ["node","--import","tsx","src/index.ts"]
CMD ["--mode=poll"]
