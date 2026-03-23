#!/usr/bin/env bash
# scripts/setup-self-hosted.sh
#
# One-shot bootstrap for a self-hosted ClawHub instance.
# Run this on the machine where Docker Compose will run.
#
# Usage:
#   bash scripts/setup-self-hosted.sh
#
# What it does:
#   1. Checks prerequisites (Docker, Bun/Node)
#   2. Creates .env.docker from the example template
#   3. Generates CONVEX_SELF_HOSTED_ADMIN_KEY
#   4. Starts the Convex backend
#   5. Deploys Convex functions to the local backend
#   6. Generates JWT signing keys (AUTH_GITHUB_*)
#   7. Starts the full stack

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[setup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }
require() { command -v "$1" &>/dev/null || { error "$1 is required but not installed."; exit 1; }; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
require docker
require bun

if ! docker compose version &>/dev/null; then
  error "docker compose (v2) is required. Install Docker Desktop or the compose plugin."
  exit 1
fi

# ── .env.docker ───────────────────────────────────────────────────────────────
if [[ ! -f .env.docker ]]; then
  info "Creating .env.docker from template..."
  cp .env.docker.example .env.docker
  info "→ .env.docker created."
else
  info ".env.docker already exists — skipping copy."
fi

# ── Admin key ─────────────────────────────────────────────────────────────────
if grep -q '^CONVEX_SELF_HOSTED_ADMIN_KEY=$' .env.docker; then
  ADMIN_KEY=$(openssl rand -hex 32)
  # Use portable sed (works on both macOS and Linux)
  sed -i.bak "s|^CONVEX_SELF_HOSTED_ADMIN_KEY=.*|CONVEX_SELF_HOSTED_ADMIN_KEY=${ADMIN_KEY}|" .env.docker
  rm -f .env.docker.bak
  info "Generated CONVEX_SELF_HOSTED_ADMIN_KEY and saved to .env.docker."
else
  info "CONVEX_SELF_HOSTED_ADMIN_KEY already set — skipping."
fi

# ── GitHub OAuth reminder ─────────────────────────────────────────────────────
GITHUB_ID=$(grep '^AUTH_GITHUB_ID=' .env.docker | cut -d= -f2-)
if [[ -z "$GITHUB_ID" ]]; then
  warn "AUTH_GITHUB_ID is empty."
  warn "Create a GitHub OAuth App at https://github.com/settings/developers"
  warn "  Homepage URL:           http://localhost"
  warn "  Authorization callback: http://localhost:3210/api/auth/callback/github"
  warn "Then set AUTH_GITHUB_ID and AUTH_GITHUB_SECRET in .env.docker and re-run."
  echo
fi

# ── Start Convex backend ──────────────────────────────────────────────────────
info "Starting Convex backend..."
docker compose up convex -d

info "Waiting for Convex backend to be ready..."
RETRIES=30
until docker compose exec convex wget -qO- http://localhost:3210/version &>/dev/null; do
  RETRIES=$((RETRIES - 1))
  if [[ $RETRIES -le 0 ]]; then
    error "Convex backend did not become healthy in time."
    docker compose logs convex | tail -20
    exit 1
  fi
  sleep 2
done
info "Convex backend is ready."

# ── Load env vars ─────────────────────────────────────────────────────────────
set -a; source .env.docker; set +a

CONVEX_URL="${CONVEX_SELF_HOSTED_URL:-http://localhost:3210}"
ADMIN_KEY="${CONVEX_SELF_HOSTED_ADMIN_KEY}"

# ── Deploy Convex functions ───────────────────────────────────────────────────
info "Deploying Convex functions to self-hosted backend..."
CONVEX_SELF_HOSTED_ADMIN_KEY="${ADMIN_KEY}" \
  bunx convex deploy \
    --url "${CONVEX_URL}" \
    --admin-key "${ADMIN_KEY}" \
    --yes
info "Convex functions deployed."

# ── Set Convex environment variables ─────────────────────────────────────────
info "Configuring Convex backend environment variables..."
convex_env_set() {
  local key="$1" val="$2"
  [[ -z "$val" ]] && return
  CONVEX_SELF_HOSTED_ADMIN_KEY="${ADMIN_KEY}" \
    bunx convex env set "${key}" "${val}" \
      --url "${CONVEX_URL}" \
      --admin-key "${ADMIN_KEY}"
}

convex_env_set SITE_URL           "${SITE_URL:-http://localhost}"
convex_env_set CONVEX_SITE_URL    "${CONVEX_SITE_URL:-$CONVEX_URL}"
convex_env_set AUTH_GITHUB_ID     "${AUTH_GITHUB_ID:-}"
convex_env_set AUTH_GITHUB_SECRET "${AUTH_GITHUB_SECRET:-}"
convex_env_set TRUST_FORWARDED_IPS "${TRUST_FORWARDED_IPS:-true}"

[[ -n "${OPENAI_API_KEY:-}"   ]] && convex_env_set OPENAI_API_KEY    "${OPENAI_API_KEY}"
[[ -n "${VT_API_KEY:-}"       ]] && convex_env_set VT_API_KEY        "${VT_API_KEY}"
[[ -n "${DISCORD_WEBHOOK_URL:-}" ]] && convex_env_set DISCORD_WEBHOOK_URL "${DISCORD_WEBHOOK_URL}"
[[ -n "${GITHUB_TOKEN:-}"     ]] && convex_env_set GITHUB_TOKEN      "${GITHUB_TOKEN}"
[[ -n "${GITHUB_APP_ID:-}"    ]] && convex_env_set GITHUB_APP_ID     "${GITHUB_APP_ID}"
[[ -n "${GITHUB_APP_PRIVATE_KEY:-}" ]] && convex_env_set GITHUB_APP_PRIVATE_KEY "${GITHUB_APP_PRIVATE_KEY}"
[[ -n "${GITHUB_APP_INSTALLATION_ID:-}" ]] && convex_env_set GITHUB_APP_INSTALLATION_ID "${GITHUB_APP_INSTALLATION_ID}"

# ── Generate JWT signing keys ─────────────────────────────────────────────────
JWT_CHECK=$(grep '^JWT_PRIVATE_KEY=' .env.docker | cut -d= -f2-)
if [[ -z "$JWT_CHECK" ]]; then
  info "Generating JWT signing keys via @convex-dev/auth..."
  warn "This will prompt you — choose 'yes' to set the keys on the Convex backend."
  CONVEX_SELF_HOSTED_ADMIN_KEY="${ADMIN_KEY}" \
    CONVEX_URL="${CONVEX_URL}" \
    bunx @convex-dev/auth
  warn "Copy the JWT_PRIVATE_KEY and JWKS values printed above into .env.docker."
else
  info "JWT_PRIVATE_KEY already set in .env.docker — setting on Convex backend..."
  convex_env_set JWT_PRIVATE_KEY "${JWT_CHECK}"
  JWKS_VAL=$(grep '^JWKS=' .env.docker | cut -d= -f2-)
  [[ -n "$JWKS_VAL" ]] && convex_env_set JWKS "${JWKS_VAL}"
fi

# ── Seed sample data ──────────────────────────────────────────────────────────
info "Seeding sample data..."
CONVEX_SELF_HOSTED_ADMIN_KEY="${ADMIN_KEY}" \
  bunx convex run --url "${CONVEX_URL}" --admin-key "${ADMIN_KEY}" --no-push \
    devSeed:seedNixSkills || warn "Seed failed — run manually after stack is up."
CONVEX_SELF_HOSTED_ADMIN_KEY="${ADMIN_KEY}" \
  bunx convex run --url "${CONVEX_URL}" --admin-key "${ADMIN_KEY}" --no-push \
    statsMaintenance:updateGlobalStatsInternal || true

# ── Build and start the full stack ────────────────────────────────────────────
info "Building and starting the full stack..."
docker compose up --build -d

info ""
info "✅  ClawHub is running!"
info "   Web UI:        http://localhost"
info "   Convex API:    ${CONVEX_URL}"
info ""
info "Next steps:"
info "  1. If you haven't already, set AUTH_GITHUB_ID + AUTH_GITHUB_SECRET in .env.docker"
info "     and re-run:  docker compose up app --build -d"
info "  2. To test the API:"
info "     curl http://localhost/api/v1/search?q=test"
info "  3. To use the CLI:"
info "     CLAWHUB_REGISTRY=http://localhost clawhub search padel"
info "  4. Full guide: docs/self-hosting.md"
