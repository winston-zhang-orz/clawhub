---
summary: "Step-by-step guide to run ClawHub on your own server."
read_when:
  - Self-hosting or air-gapped deployment
  - Running a private skill registry
---

# Self-Hosting ClawHub

This guide walks through deploying ClawHub completely on your own infrastructure using Docker
Compose. No Vercel account, no Convex cloud subscription — everything runs locally.

## Architecture

```
Browser / CLI
      │
      ▼
  nginx :80          ← reverse proxy (replaces vercel.json rewrites)
    ├─ /api/*  ──►  convex-backend :3210   ← DB + HTTP actions + file storage
    └─ /*      ──►  TanStack Start  :3000  ← SSR frontend
```

## Prerequisites

| Requirement | Version |
|-------------|---------|
| Docker + Docker Compose v2 | Docker 24+ |
| Bun (for function deploy + JWT keygen) | 1.x |
| GitHub OAuth App | — |
| OpenAI API key (optional) | — |

## Quick start (automated)

```bash
# 1. Clone the repo
git clone https://github.com/your-fork/clawhub.git
cd clawhub

# 2. Install JS dependencies (needed for the deploy script)
bun install

# 3. Run the setup script — it walks you through every step
bash scripts/setup-self-hosted.sh
```

The script:
- Creates `.env.docker` from the template
- Generates a random Convex admin key
- Starts the Convex backend
- Deploys the Convex functions
- Generates JWT signing keys
- Seeds sample data
- Builds and starts the full stack

---

## Manual setup (step by step)

### Step 1 — Create your environment file

```bash
cp .env.docker.example .env.docker
```

Open `.env.docker` and fill in the values. Mandatory items are marked below.

### Step 2 — Create a GitHub OAuth App

1. Go to <https://github.com/settings/developers> → **OAuth Apps** → **New OAuth App**
2. Set these fields:

   | Field | Value |
   |-------|-------|
   | Application name | ClawHub (self-hosted) |
   | Homepage URL | `http://localhost` (or your domain) |
   | Authorization callback URL | `http://localhost:3210/api/auth/callback/github` |

3. Copy the **Client ID** and generate a **Client Secret**.
4. In `.env.docker`:

   ```bash
   AUTH_GITHUB_ID=<client-id>
   AUTH_GITHUB_SECRET=<client-secret>
   ```

### Step 3 — Generate a Convex admin key

```bash
export ADMIN_KEY=$(openssl rand -hex 32)
# Set it in .env.docker:
sed -i "s|^CONVEX_SELF_HOSTED_ADMIN_KEY=.*|CONVEX_SELF_HOSTED_ADMIN_KEY=${ADMIN_KEY}|" .env.docker
```

### Step 4 — Start the Convex backend

```bash
docker compose up convex -d
# Wait for it to be healthy:
docker compose ps
```

### Step 5 — Deploy Convex functions

The Convex backend is just the runtime — it needs your functions deployed to it.

```bash
source .env.docker

CONVEX_SELF_HOSTED_ADMIN_KEY="${CONVEX_SELF_HOSTED_ADMIN_KEY}" \
  bunx convex deploy \
    --url "${CONVEX_SELF_HOSTED_URL}" \
    --admin-key "${CONVEX_SELF_HOSTED_ADMIN_KEY}" \
    --yes
```

### Step 6 — Configure backend environment variables

```bash
source .env.docker
URL="${CONVEX_SELF_HOSTED_URL}"
KEY="${CONVEX_SELF_HOSTED_ADMIN_KEY}"

# Required
bunx convex env set SITE_URL         "${SITE_URL}"          --url "$URL" --admin-key "$KEY"
bunx convex env set CONVEX_SITE_URL  "${CONVEX_SITE_URL}"   --url "$URL" --admin-key "$KEY"
bunx convex env set AUTH_GITHUB_ID   "${AUTH_GITHUB_ID}"    --url "$URL" --admin-key "$KEY"
bunx convex env set AUTH_GITHUB_SECRET "${AUTH_GITHUB_SECRET}" --url "$URL" --admin-key "$KEY"
bunx convex env set TRUST_FORWARDED_IPS "true"              --url "$URL" --admin-key "$KEY"

# Optional — features degrade gracefully without these
bunx convex env set OPENAI_API_KEY   "${OPENAI_API_KEY}"    --url "$URL" --admin-key "$KEY"
bunx convex env set VT_API_KEY       "${VT_API_KEY}"        --url "$URL" --admin-key "$KEY"
```

### Step 7 — Generate JWT signing keys

```bash
source .env.docker
CONVEX_SELF_HOSTED_ADMIN_KEY="${CONVEX_SELF_HOSTED_ADMIN_KEY}" \
CONVEX_URL="${CONVEX_SELF_HOSTED_URL}" \
  bunx @convex-dev/auth
```

When prompted, choose **yes** to push the keys to the Convex backend. Copy the printed
`JWT_PRIVATE_KEY` and `JWKS` values into `.env.docker`.

### Step 8 — Seed sample data (optional)

```bash
source .env.docker
URL="${CONVEX_SELF_HOSTED_URL}"; KEY="${CONVEX_SELF_HOSTED_ADMIN_KEY}"

bunx convex run --url "$URL" --admin-key "$KEY" --no-push devSeed:seedNixSkills
bunx convex run --url "$URL" --admin-key "$KEY" --no-push statsMaintenance:updateGlobalStatsInternal
```

### Step 9 — Build and start the full stack

```bash
docker compose up --build -d
```

The first build downloads ~600 MB of layers and compiles the frontend; subsequent builds are much
faster thanks to Docker layer caching.

---

## Verify the deployment

```bash
# Health check
curl -i http://localhost/api/v1/search?q=test
curl -i http://localhost/api/v1/skills/padel

# CLI smoke test
CLAWHUB_REGISTRY=http://localhost clawhub search padel
CLAWHUB_REGISTRY=http://localhost CLAWHUB_SITE=http://localhost clawhub login
clawhub whoami
```

---

## Deploying on a custom domain

If you have a domain (e.g. `skills.company.internal`), update these values and rebuild:

**`.env.docker`:**
```bash
CONVEX_SELF_HOSTED_URL=https://skills.company.internal:3210
VITE_CONVEX_URL=https://skills.company.internal:3210
VITE_CONVEX_SITE_URL=https://skills.company.internal:3210
CONVEX_SITE_URL=https://skills.company.internal:3210
SITE_URL=https://skills.company.internal
```

**GitHub OAuth App:** update the callback URL to:
```
https://skills.company.internal:3210/api/auth/callback/github
```

**`nginx/nginx.conf`:** add your TLS certificate if you terminate HTTPS at nginx. Example using
Let's Encrypt / Certbot:
```nginx
server {
    listen 443 ssl;
    server_name skills.company.internal;
    ssl_certificate     /etc/letsencrypt/live/skills.company.internal/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/skills.company.internal/privkey.pem;
    # ... rest of the config
}
```

---

## CLI discovery

The CLI auto-discovers registry configuration from `/.well-known/clawhub.json`. Your nginx already
serves this file through the frontend if the route exists. You can also point the CLI directly:

```bash
export CLAWHUB_REGISTRY=http://localhost
export CLAWHUB_SITE=http://localhost
clawhub search test
```

---

## Environment variable reference

All variables are documented in `.env.docker.example`.

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `CONVEX_SELF_HOSTED_URL` | ✅ | `http://localhost:3210` | External URL of the Convex backend |
| `CONVEX_SELF_HOSTED_ADMIN_KEY` | ✅ | _(generated)_ | Convex admin access key |
| `VITE_CONVEX_URL` | ✅ | — | Convex URL embedded in the browser bundle |
| `VITE_CONVEX_SITE_URL` | ✅ | — | Convex site URL embedded in the browser bundle |
| `AUTH_GITHUB_ID` | ✅ | — | GitHub OAuth App client ID |
| `AUTH_GITHUB_SECRET` | ✅ | — | GitHub OAuth App client secret |
| `JWT_PRIVATE_KEY` | ✅ | — | JWT signing key (from `bunx @convex-dev/auth`) |
| `JWKS` | ✅ | — | JWKS public key set (from `bunx @convex-dev/auth`) |
| `OPENAI_API_KEY` | optional | — | Enables vector search + LLM moderation |
| `VT_API_KEY` | optional | — | Enables VirusTotal malware scanning |
| `DISCORD_WEBHOOK_URL` | optional | — | Enables Discord skill notifications |
| `GITHUB_TOKEN` | optional | — | Raises publish gate rate limit |
| `GITHUB_APP_ID` / `GITHUB_APP_PRIVATE_KEY` / `GITHUB_APP_INSTALLATION_ID` | optional | — | Enables GitHub skill backup |
| `TRUST_FORWARDED_IPS` | optional | `true` | Trust nginx `X-Forwarded-For` header |

---

## Data persistence

Convex stores all data (documents + uploaded files) in a Docker volume (`convex_data`). Back this
up regularly:

```bash
docker compose stop convex
docker run --rm \
  -v clawhub_convex_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/convex-$(date +%Y%m%d).tar.gz /data
docker compose start convex
```

---

## Upgrading

```bash
# Pull latest Convex backend image
docker compose pull convex
docker compose up convex -d

# Re-deploy Convex functions after source changes
source .env.docker
bunx convex deploy \
  --url "${CONVEX_SELF_HOSTED_URL}" \
  --admin-key "${CONVEX_SELF_HOSTED_ADMIN_KEY}" \
  --yes

# Rebuild and restart the frontend
docker compose up app --build -d
```

---

## Troubleshooting

### `401 MissingAccessToken` from Convex

The `JWT_PRIVATE_KEY` and `JWKS` are not set on the Convex backend. Run:
```bash
source .env.docker
bunx convex env set JWT_PRIVATE_KEY "${JWT_PRIVATE_KEY}" \
  --url "${CONVEX_SELF_HOSTED_URL}" --admin-key "${CONVEX_SELF_HOSTED_ADMIN_KEY}"
bunx convex env set JWKS "${JWKS}" \
  --url "${CONVEX_SELF_HOSTED_URL}" --admin-key "${CONVEX_SELF_HOSTED_ADMIN_KEY}"
```

### GitHub OAuth returns "redirect_uri_mismatch"

The callback URL in your GitHub OAuth App must exactly match:
```
http://<CONVEX_SELF_HOSTED_URL>/api/auth/callback/github
```
Update the OAuth App at <https://github.com/settings/developers>.

### Search returns no results / empty

`OPENAI_API_KEY` is optional — without it, skills are stored with zero-vectors and keyword search
does not work. Set the key and re-publish to generate embeddings.

### Rate limits collapse multiple users into one IP

Ensure `TRUST_FORWARDED_IPS=true` is set in `.env.docker` and the Convex backend env. nginx in
this stack forwards the real client IP in `X-Forwarded-For`.

### View logs

```bash
docker compose logs -f           # all services
docker compose logs -f convex    # Convex backend only
docker compose logs -f app       # frontend only
docker compose logs -f nginx     # nginx only
```
