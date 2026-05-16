# Smebes — ABS upgrade to v1.0.4 (one-paste)

**Target tag:** `v1.0.4` (Sprint 2N.3 GA — image content identical to v1.0.3,
ships under `ghcr.io/automatiabcn/abs-*`).

## Why upgrade

- Sprint 2N.2 v1.0.3 was the first tag whose customer images are
  workflow-published to `ghcr.io/automatiabcn/abs-*`. Smebes' pre-2N.2
  install (v1.0.0 / v1.0.1) still pulls from `ghcr.io/enzoemir1/abs-*`.
- v1.0.4 closes the v1.0.3 docs-site gap; runtime payload is identical.
- Upgrading also moves smebes to the workflow-published namespace so
  future tags (1.0.5+) pull without founder-side dual-publish.

## One-paste (run on the smebes server, root or sudoer)

```sh
set -euo pipefail
cd /opt/abs    # adjust to the actual install path on smebes

# Backup .env before any change.
cp -a .env .env.bak.$(date +%Y%m%d-%H%M%S)

# Pin to v1.0.4 + switch to the workflow-published namespace.
sed -i 's/^ABS_VERSION=.*/ABS_VERSION=1.0.4/' .env
if grep -q '^ABS_GHCR_NAMESPACE=' .env; then
  sed -i 's|^ABS_GHCR_NAMESPACE=.*|ABS_GHCR_NAMESPACE=automatiabcn|' .env
else
  echo 'ABS_GHCR_NAMESPACE=automatiabcn' >> .env
fi

# Re-login to ghcr.io with the read-only PAT under keys/ghcr_pull.token.
cat keys/ghcr_pull.token | docker login ghcr.io \
  -u "${GHCR_USER:-smebes-readonly}" --password-stdin

# Pull + rotate.
docker compose -f infra/docker-compose.customer.yml pull
docker compose -f infra/docker-compose.customer.yml up -d

# Health verify.
sleep 8
curl -sf "https://${ABS_PUBLIC_HOSTNAME}/healthz" && echo " healthz OK"
curl -sf "https://${ABS_PUBLIC_HOSTNAME}/readyz"  && echo " readyz OK"

# Image identity for the audit log.
docker compose -f infra/docker-compose.customer.yml \
  images --format '{{.Service}}  {{.Repository}}:{{.Tag}}  {{.ID}}'
```

Expected `/readyz` body includes `"version":"1.0.4"` and
`"db":{"status":"ok"}`. If `/readyz` returns 503, see `Rollback` below.

## Rollback (back to v1.0.3 — same namespace, just retag)

```sh
set -euo pipefail
cd /opt/abs

sed -i 's/^ABS_VERSION=.*/ABS_VERSION=1.0.3/' .env
docker compose -f infra/docker-compose.customer.yml pull
docker compose -f infra/docker-compose.customer.yml up -d
sleep 8
curl -sf "https://${ABS_PUBLIC_HOSTNAME}/readyz" && echo " readyz OK on 1.0.3"
```

If the rollback also fails, fall back to the pre-2N.2 namespace:

```sh
sed -i 's|^ABS_GHCR_NAMESPACE=.*|ABS_GHCR_NAMESPACE=enzoemir1|' .env
sed -i 's/^ABS_VERSION=.*/ABS_VERSION=1.0.1/' .env
docker compose -f infra/docker-compose.customer.yml pull
docker compose -f infra/docker-compose.customer.yml up -d
```

## Verification checklist (founder sign-off)

- [ ] `/readyz` 200 with `"version":"1.0.4"`
- [ ] Backend container image SHA matches
  `ghcr.io/automatiabcn/abs-backend:1.0.4` digest
  `sha256:459bb68e9ad8b6...` (FAZ B evidence)
- [ ] Landing container image SHA matches
  `ghcr.io/automatiabcn/abs-landing:1.0.4`
- [ ] `.env.bak.*` restored if rollback was needed; otherwise archived
- [ ] Pilot contract metadata updated v1.0.x → v1.0.4
