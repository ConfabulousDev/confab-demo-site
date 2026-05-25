variable "linode_token" {
  description = "Linode API personal access token (read/write for Linodes + Firewalls)."
  type        = string
  sensitive   = true
}

variable "ssh_authorized_keys" {
  description = "Public SSH keys authorized for root + deploy user on the VM."
  type        = list(string)
}

variable "postgres_password" {
  description = "Password for the bundled Postgres `confab` user."
  type        = string
  sensitive   = true
}

variable "minio_root_user" {
  description = "MinIO root username. Used as AWS_ACCESS_KEY_ID by the app + worker."
  type        = string
  default     = "confab-demo"
}

variable "minio_root_password" {
  description = "MinIO root password. Used as AWS_SECRET_ACCESS_KEY by the app + worker."
  type        = string
  sensitive   = true
}

variable "csrf_secret_key" {
  description = "App CSRF secret. Generate with `openssl rand -base64 32`."
  type        = string
  sensitive   = true
}

variable "admin_bootstrap_email" {
  description = "Email for the initial admin account, created on first boot. The account row persists; ADMIN_BOOTSTRAP_* env vars can be removed from .env on the VM after first successful login."
  type        = string
}

variable "admin_bootstrap_password" {
  description = "Password for the initial admin account. Remove from .env on the VM after first login."
  type        = string
  sensitive   = true
}

variable "super_admin_emails" {
  description = "Comma-separated list of emails granted super-admin access in the app."
  type        = string
}

variable "support_email" {
  description = "Support email surfaced in the app UI."
  type        = string
}

variable "anthropic_api_key" {
  description = "Dedicated Anthropic API key. Set a hard monthly billing cap on the account."
  type        = string
  sensitive   = true
}
