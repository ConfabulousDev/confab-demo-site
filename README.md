# confab-demo-site

Infra-as-code for [`demo.confabulous.dev`](https://demo.confabulous.dev) — the public, read-only Confabulous demo instance. Published as a worked example of self-hosting Confabulous; the canonical guide is [`confab-web/SELF-HOSTING.md`](https://github.com/ConfabulousDev/confab-web/blob/main/SELF-HOSTING.md).

Single Linode VM (~$7/mo: $5 Nanode 1GB + $2 Backups) running the standard self-hosting docker-compose stack — Postgres, MinIO, app, worker, Caddy — behind Cloudflare DNS-only.

## What's here

- `tofu/` — Linode VM provisioning. Uses the `linode/linode` provider. DNS is added manually in Cloudflare (see below).
- `stack/` — `docker-compose.yml`, `Caddyfile`, `.env.example` for the demo stack. Source-of-truth; rendered onto the VM by cloud-init at first boot.
- `scripts/deploy.sh` — sync `docker-compose.yml` + `Caddyfile` to the VM, pull the pinned app and MinIO images, run migrations, restart containers. It renders `.env` from OpenTofu state; `tofu/terraform.tfvars` is the source for secrets.

## Adapt for your own deployment

This repo deploys the literal `demo.confabulous.dev`. Before applying it as-is to your own infra:

**Domain & deploy target**
- Replace `demo.confabulous.dev` in `stack/Caddyfile`, `stack/docker-compose.yml`, the trailing DNS comment in `tofu/main.tf`, and the `VM_HOST` default in `scripts/deploy.sh`.

**Auth & emails**
- Set the admin / super-admin / support emails in `tofu/terraform.tfvars`, and update `ALLOWED_EMAIL_DOMAINS` in `stack/docker-compose.yml` to match.

**Demo-mode toggles** — the compose file is configured for an anonymous-readable demo. For a normal multi-user instance:
- Remove `DEMO_IDENTITY_EMAIL` (or the app will auto-impersonate anonymous visitors as that user)
- Change `MAX_USERS: "0"` to a positive number (or remove the line to leave unlimited)
- Flip `ENABLE_SHARE_CREATION` and `SHARE_ALL_SESSIONS_TO_AUTHENTICATED` to your preference

**Smart Recap** — enabled by default with a dedicated Anthropic key. To turn off, set `SMART_RECAP_ENABLED=false` in `stack/docker-compose.yml` and leave `anthropic_api_key` blank in `tofu/terraform.tfvars`.

**Linode-side cosmetic** — region is `us-west` (Fremont); resource labels are `confab-demo` and `confab-demo-fw`. Change in `tofu/main.tf` as needed.

**Secrets** — generate fresh values; see `tofu/terraform.tfvars.example` and `stack/.env.example`.

## One-time provisioning

Requires [OpenTofu](https://opentofu.org) (or Terraform) ≥ 1.5.

```sh
cd tofu
cp terraform.tfvars.example terraform.tfvars  # fill in secrets
tofu init
tofu apply
```

`terraform.tfvars` is gitignored. Real secrets stay on your laptop.

### DNS (manual step)

After `tofu apply`, copy the `vm_ip` output and add an A record in Cloudflare:

- Name: `demo`
- Content: `<vm_ip>`
- Proxy status: **DNS only** (grey cloud)
- TTL: Auto

Cloudflare API access is intentionally not part of the OpenTofu config — keeping the demo zone token off this repo means a leaked secret can't touch prod DNS.

### SSH access

`tofu apply` locks the firewall's SSH rule to the public IP of the machine running it (looked up at apply time via `https://ipv4.icanhazip.com`). If your IP changes — different network, VPN flip — re-run `tofu apply` to refresh the allowlist before using `scripts/deploy.sh`. Ports 80/443 stay open to the world.

## Deploying updates

The running version is available at `https://demo.confabulous.dev/api/v1/version`.
To upgrade, review release notes since that version, change the single
`x-confab-image` tag in `stack/docker-compose.yml`, and reconcile the stack
with the release's self-hosting Compose file. The migrate, app, and worker
services all use that tag. MinIO images are also pinned in the Compose file.
Before running migrations, confirm a recent Linode backup or take a database
backup; schema and data migrations may complicate rollback.

```sh
./scripts/deploy.sh
curl -fsS https://demo.confabulous.dev/api/v1/version
```

The script syncs `stack/docker-compose.yml` and `Caddyfile`, pulls the pinned
app and MinIO images, runs DB migrations, and restarts containers. It renders
`.env` from the OpenTofu `env_file` output on each deploy. Edit
`tofu/terraform.tfvars` for secret or email changes; the drift guard stops
unexpected changes to existing live values. The script does not pull new
Postgres or Caddy images during an app upgrade.

## Stack reference

The compose stack is intentionally close to the one published in `confab-web/SELF-HOSTING.md`. Where it diverges, treat that as a candidate fix upstream rather than a demo-only patch.
