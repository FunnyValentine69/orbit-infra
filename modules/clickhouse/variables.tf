variable "name" {
  description = "Service name"
  type        = string
  default     = "clickhouse"
}

variable "env_id" {
  description = "Ephemeral environment identifier, applied as the env_id tag on every taggable resource"
  type        = string
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
  # P3-2 replaces this with the private-ECR mirror digest of this image.
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
