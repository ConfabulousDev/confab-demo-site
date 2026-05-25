#!/bin/sh
#
# Sync stack config to demo.confabulous.dev, pull the latest confab-web image,
# and roll it out.
#
# What this does: scp `stack/docker-compose.yml` and `stack/Caddyfile` to
# /opt/confab/ on the VM, then SSH in: `docker compose pull` (refreshes images),
# `docker compose run --rm migrate` (applies new DB migrations), `docker compose
# up -d` (recreates containers whose image or config changed). Postgres + MinIO
# volumes are untouched.
#
# What this does NOT do: change infra (use `tofu apply`), change secrets
# (edit /opt/confab/.env on the VM directly), or take a pre-deploy snapshot
# (rely on Linode Backups for rollback).
#
# Migration failure leaves the stack in a crash-loop until manually fixed:
# SSH in, inspect schema_migrations, then `migrate force <version>` or
# `down` depending on what failed.

set -eu

VM_HOST="${VM_HOST:-demo.confabulous.dev}"
VM_USER="${VM_USER:-deploy}"
STACK_DIR="$(cd "$(dirname "$0")/../stack" && pwd)"

echo "Deploying to ${VM_USER}@${VM_HOST}..."

echo "→ scp stack/ → /opt/confab/"
scp "${STACK_DIR}/docker-compose.yml" "${STACK_DIR}/Caddyfile" "${VM_USER}@${VM_HOST}:/opt/confab/"

ssh "${VM_USER}@${VM_HOST}" '
  set -e
  cd /opt/confab
  echo "→ docker compose pull"
  docker compose pull
  echo "→ docker compose run --rm migrate"
  docker compose run --rm migrate
  echo "→ docker compose up -d"
  docker compose up -d
  echo "→ docker compose ps"
  docker compose ps
'

echo "Deploy complete."
