#!/bin/sh
#
# Sync stack config to demo.confabulous.dev, pull the latest confab-web image,
# and roll it out.
#
# What this does: render /opt/confab/.env from tofu (so terraform.tfvars stays
# the single source of truth — see the `env_file` output), scp it plus
# `stack/docker-compose.yml` and `stack/Caddyfile` to the VM, then SSH in:
# `docker compose pull` (refreshes images), `docker compose run --rm migrate`
# (applies new DB migrations), `docker compose up -d` (recreates containers
# whose image, config, or env changed). Postgres + MinIO volumes are untouched.
#
# Because .env is re-rendered every deploy, edit secrets/emails in
# tofu/terraform.tfvars and run this — manual edits to /opt/confab/.env get
# overwritten. (ADMIN_BOOTSTRAP_PASSWORD is re-added each deploy; that's
# harmless — bootstrap only creates the admin row if it doesn't already exist.)
#
# Before overwriting, a drift guard diffs the rendered .env against the live
# one and ABORTS if it would change or drop the value of any existing key
# (e.g. a POSTGRES_PASSWORD in tfvars that doesn't match the running DB).
# Adding new keys is fine. Intentionally rotating a secret? Re-run with
# DEPLOY_ALLOW_ENV_DRIFT=1 to bypass the guard.
#
# What this does NOT do: change infra (use `tofu apply`) or take a pre-deploy
# snapshot (rely on Linode Backups for rollback).
#
# Migration failure leaves the stack in a crash-loop until manually fixed:
# SSH in, inspect schema_migrations, then `migrate force <version>` or
# `down` depending on what failed.

set -eu

VM_HOST="${VM_HOST:-demo.confabulous.dev}"
VM_USER="${VM_USER:-deploy}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/../stack" && pwd)"
TOFU_DIR="$(cd "${SCRIPT_DIR}/../tofu" && pwd)"

# OpenTofu preferred; fall back to Terraform.
if command -v tofu >/dev/null 2>&1; then
  TF=tofu
elif command -v terraform >/dev/null 2>&1; then
  TF=terraform
else
  echo "error: neither 'tofu' nor 'terraform' found on PATH" >&2
  exit 1
fi

# Render .env from tfvars into private temp files, cleaned up on exit.
ENV_TMP="$(mktemp)"
HAVE_TMP="$(mktemp)"
trap 'rm -f "${ENV_TMP}" "${HAVE_TMP}"' EXIT
echo "→ render .env from ${TF} (env_file output)"
"${TF}" -chdir="${TOFU_DIR}" output -raw env_file > "${ENV_TMP}"

# Guard against shipping an empty/garbage .env that would wipe live secrets.
if ! grep -q '^POSTGRES_PASSWORD=.' "${ENV_TMP}"; then
  echo "error: rendered .env looks empty or malformed; aborting" >&2
  exit 1
fi

# Drift guard: refuse to overwrite the live .env if doing so would change or
# drop the value of an existing key (a working secret that diverges from
# tfvars). New keys are fine. Skipped on a fresh VM with no .env yet, or when
# DEPLOY_ALLOW_ENV_DRIFT=1 is set (deliberate secret rotation).
if [ "${DEPLOY_ALLOW_ENV_DRIFT:-0}" = "1" ]; then
  echo "→ drift guard bypassed (DEPLOY_ALLOW_ENV_DRIFT=1)"
elif ssh "${VM_USER}@${VM_HOST}" 'sudo cat /opt/confab/.env 2>/dev/null' > "${HAVE_TMP}" && [ -s "${HAVE_TMP}" ]; then
  # Compare keys present in BOTH: report any whose value changed, plus any live
  # key the rendered file would drop. Values may contain '=' (base64), so split
  # on the first '=' only. NR==FNR pass loads the rendered ("want") values.
  drift="$(awk '
    NR==FNR {
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { eq=index($0,"="); want[substr($0,1,eq-1)]=substr($0,eq+1) }
      next
    }
    $0 ~ /^[A-Za-z_][A-Za-z0-9_]*=/ {
      eq=index($0,"="); k=substr($0,1,eq-1); v=substr($0,eq+1)
      if (k in want) { if (want[k] != v) print "  would change: " k }
      else print "  would drop:   " k
    }
  ' "${ENV_TMP}" "${HAVE_TMP}")"
  if [ -n "${drift}" ]; then
    echo "error: refusing to deploy — rendered .env diverges from the live .env:" >&2
    echo "${drift}" >&2
    echo "Reconcile tofu/terraform.tfvars with the live values first." >&2
    echo "If this is a deliberate rotation, re-run: DEPLOY_ALLOW_ENV_DRIFT=1 $0" >&2
    exit 1
  fi
  echo "→ drift guard passed (additions only, no value changes)"
else
  echo "→ no live .env found (fresh VM?); skipping drift guard"
fi

echo "Deploying to ${VM_USER}@${VM_HOST}..."

echo "→ scp stack/ + .env → VM"
scp "${STACK_DIR}/docker-compose.yml" "${STACK_DIR}/Caddyfile" "${VM_USER}@${VM_HOST}:/opt/confab/"
scp "${ENV_TMP}" "${VM_USER}@${VM_HOST}:/tmp/confab.env"

ssh "${VM_USER}@${VM_HOST}" '
  set -e
  cd /opt/confab
  echo "→ install .env (root:docker 0640)"
  sudo install -o root -g docker -m 640 /tmp/confab.env /opt/confab/.env
  rm -f /tmp/confab.env
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
