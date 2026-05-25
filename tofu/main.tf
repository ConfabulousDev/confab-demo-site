terraform {
  required_version = ">= 1.5"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

# SSH is locked to the public IP of whoever runs `tofu apply`. If your IP
# changes, re-run apply from the new network to refresh the allowlist.
data "http" "ssh_source_ip" {
  url = "https://ipv4.icanhazip.com"
}

# Cloud-init user-data rendered with secrets + checked-in compose/Caddyfile.
locals {
  ssh_cidr = "${chomp(data.http.ssh_source_ip.response_body)}/32"
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    ssh_authorized_keys      = var.ssh_authorized_keys
    compose_yml_b64          = base64encode(file("${path.module}/../stack/docker-compose.yml"))
    caddyfile_b64            = base64encode(file("${path.module}/../stack/Caddyfile"))
    postgres_password        = var.postgres_password
    minio_root_user          = var.minio_root_user
    minio_root_password      = var.minio_root_password
    csrf_secret_key          = var.csrf_secret_key
    admin_bootstrap_email    = var.admin_bootstrap_email
    admin_bootstrap_password = var.admin_bootstrap_password
    super_admin_emails       = var.super_admin_emails
    support_email            = var.support_email
    anthropic_api_key        = var.anthropic_api_key
  })
}

resource "linode_instance" "demo" {
  label            = "confab-demo"
  region           = "us-west" # Fremont
  type             = "g6-nanode-1"
  image            = "linode/debian12"
  authorized_keys  = var.ssh_authorized_keys
  backups_enabled  = true
  tags             = ["confab", "demo"]

  metadata {
    user_data = base64encode(local.user_data)
  }

  # Cloud-init only runs at first boot, so post-provision changes to user_data
  # (driven by compose/Caddyfile/cloud-init edits) don't affect the running VM
  # — but the Linode provider treats `metadata` as force-new, so the next apply
  # would otherwise destroy + recreate the instance. Stack updates flow via
  # scripts/deploy.sh; opt into a fresh provision with
  # `tofu apply -replace=linode_instance.demo`.
  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "linode_firewall" "demo" {
  label = "confab-demo-fw"

  inbound {
    label    = "allow-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = [local.ssh_cidr]
  }

  inbound {
    label    = "allow-http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [linode_instance.demo.id]
}

# DNS is managed manually in the Cloudflare dashboard.
# After `tofu apply`, take the `vm_ip` output and add an A record:
#   <your-domain> → <vm_ip>, proxied = false (grey-cloud, DNS-only).
