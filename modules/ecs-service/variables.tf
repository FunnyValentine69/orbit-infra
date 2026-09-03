variable "name" {
  description = "Service name"
  type        = string
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
}

variable "command" {
  description = "Container command override"
  type        = list(string)
  default     = null
}

variable "container_port" {
  description = "Container port"
  type        = number
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory (MiB)"
  type        = number
  default     = 512
}

variable "env" {
  description = "Plaintext environment variables"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret environment variables: name => Secrets Manager ARN"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "Subnet IDs for the service's network configuration"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the service's network configuration"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign a public IP to task ENIs"
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Enable ECS Exec (aws ecs execute-command)"
  type        = bool
  default     = true
}

variable "cloud_map_namespace_id" {
  description = "Cloud Map private DNS namespace ID; used only when register_service_discovery = true"
  type        = string
  default     = null
}

# Decoupled from cloud_map_namespace_id on purpose: count/for_each must be
# known at plan time, but a namespace created in the same apply as this
# module (the envs/preview case) has an unknown id until apply. Gating on
# a plain bool keeps that id usable as a resource attribute value (fine
# when unknown) without ever driving count/for_each with an unknown value.
variable "register_service_discovery" {
  description = "Register the service in Cloud Map under var.name. Requires cloud_map_namespace_id."
  type        = bool
  default     = false
}

variable "alb_target_group_arn" {
  description = "ALB target group ARN; when set, attaches a load_balancer block"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention, in days"
  type        = number
  default     = 7
}

variable "health_check" {
  description = "Container health check"
  type = object({
    command      = list(string)
    interval     = optional(number, 30)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 0)
  })
  default = null
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to the execution and task roles; required by the deployer policy on real AWS"
  type        = string
  default     = null
}

variable "task_role_policy_json" {
  description = "Additional inline policy document (JSON) attached to the task role"
  type        = string
  default     = null
}

variable "region" {
  description = "AWS region used for the awslogs driver. Passed in explicitly (no data source): a module-level depends_on in the caller would defer a data source to apply time and force the task definition to be replaced on every plan."
  type        = string

  validation {
    condition     = length(var.region) > 0
    error_message = "region must be set."
  }
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default     = {}
}
