variable "name" {
  description = "Service name"
  type        = string
  default     = "clickhouse"
}

variable "env_id" {
  description = "Ephemeral environment identifier, applied as the env_id tag on every taggable resource"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$", var.env_id))
    error_message = "env_id must be 1-12 lowercase letters, digits, or hyphens, starting alphanumeric, no leading or trailing hyphen: it is embedded in S3 bucket names, Cloud Map DNS names, and the 32-character IAM role prefix that the deployer policy matches on."
  }
}

variable "enabled" {
  description = "Whether to create this service at all"
  type        = bool
  default     = true
}

variable "cluster_arn" {
  description = "ECS cluster ARN to run the service in"
  type        = string
}

variable "image" {
  description = "Container image (tag or digest form)"
  type        = string
  default     = "clickhouse/clickhouse-server:24.3-alpine"
}

variable "subnet_ids" {
  description = "Subnet IDs for the service's network configuration"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the service's network configuration"
  type        = list(string)
}

variable "cloud_map_namespace_id" {
  description = "Cloud Map private DNS namespace ID; used only when register_service_discovery = true"
  type        = string
  default     = null
}

variable "register_service_discovery" {
  description = "Register the service in Cloud Map under var.name. Requires cloud_map_namespace_id."
  type        = bool
  default     = false
}

variable "namespace_name" {
  description = "Cloud Map private DNS namespace name, used only to compute the discovery_dns_name output"
  type        = string
  default     = null
}

variable "database" {
  description = "Default ClickHouse database name (CLICKHOUSE_DB)"
  type        = string
  default     = "app"
}

variable "user" {
  description = "ClickHouse username (CLICKHOUSE_USER)"
  type        = string
  default     = "default"
}

variable "password_secret_arn" {
  description = "Secrets Manager secret ARN holding the ClickHouse password, wired in as CLICKHOUSE_PASSWORD"
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to the execution and task roles; required by the deployer policy on real AWS"
  type        = string
  default     = null
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task memory (MiB)"
  type        = number
  default     = 1024
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default     = {}
}
