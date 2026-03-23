# ─────────────────────────────────────────────
# Stage 1: build the TanStack Start / Nitro app
# ─────────────────────────────────────────────
FROM oven/bun:1 AS builder

WORKDIR /app

# Copy manifests first for better layer caching
COPY package.json bun.lock* ./
COPY packages/schema/package.json ./packages/schema/
COPY packages/clawdhub/package.json ./packages/clawdhub/

RUN bun install --frozen-lockfile

# Copy full source
COPY . .

# VITE_* vars are embedded at build time by Vite.
# Pass them as build-time ARGs so the client bundle is correct.
ARG VITE_CONVEX_URL
ARG VITE_CONVEX_SITE_URL
ARG VITE_SOULHUB_SITE_URL
ARG VITE_SOULHUB_HOST
ARG VITE_SITE_MODE
ARG VITE_APP_BUILD_SHA
ARG VITE_GITLAB_URL

ENV VITE_CONVEX_URL=${VITE_CONVEX_URL}
ENV VITE_CONVEX_SITE_URL=${VITE_CONVEX_SITE_URL}
ENV VITE_SOULHUB_SITE_URL=${VITE_SOULHUB_SITE_URL}
ENV VITE_SOULHUB_HOST=${VITE_SOULHUB_HOST}
ENV VITE_SITE_MODE=${VITE_SITE_MODE}
ENV VITE_APP_BUILD_SHA=${VITE_APP_BUILD_SHA}
ENV VITE_GITLAB_URL=${VITE_GITLAB_URL}

RUN bun run build

# ─────────────────────────────────────────────
# Stage 2: minimal runtime image
# ─────────────────────────────────────────────
FROM node:20-slim AS runner

WORKDIR /app

# Copy the Nitro output bundle (self-contained Node.js server)
COPY --from=builder /app/.output ./.output

EXPOSE 3000

# Runtime env vars (server-side; not embedded in the client bundle)
ENV PORT=3000
ENV NODE_ENV=production

CMD ["node", ".output/server/index.mjs"]
