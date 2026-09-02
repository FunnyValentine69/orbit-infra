variable "target" {
  description = "Apply target: real aws or a local localstack instance"
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "localstack"], var.target)
    error_message = "target must be one of: aws, localstack."
  }
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL, used only when target = \"localstack\""
  type        = string
  default     = "http://localhost:4566"
}

variable "localstack_container_endpoint" {
  description = "LocalStack endpoint URL as reached from inside an ECS task container (not the host); used only when target = \"localstack\" to wire AWS_ENDPOINT_URL into the api task"
  type        = string
  default     = "http://host.docker.internal:4566"
}

variable "localstack_use_ambient_creds" {
  description = "When target = \"localstack\", use the ambient AWS credentials (e.g. an assumed deployer-role session) instead of the hardcoded \"test\"/\"test\" static keys. Used to prove the deployer IAM policy against LocalStack (TODO.md P2-7)."
  type        = bool
  default     = false
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Project/resource name prefix"
  type        = string
  default     = "orbit-infra-79s5rw"
}

variable "env_id" {
  description = "Ephemeral environment identifier"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$", var.env_id))
    error_message = "env_id must be 1-12 lowercase letters, digits, or hyphens, starting alphanumeric, no leading or trailing hyphen: it is embedded in S3 bucket names, Cloud Map DNS names, and the 32-character IAM role prefix that the deployer policy matches on."
  }
}

# Validated and required now so `make plan` fails fast.
variable "operator_cidr" {
  description = "CIDR allowed to reach the ALB"
  type        = string

  validation {
    condition = can(cidrhost(var.operator_cidr, 0)) && !contains(["0.0.0.0/0", "::/0"], var.operator_cidr) && can(tonumber(split("/", var.operator_cidr)[1])) && (
      strcontains(var.operator_cidr, ":") ? tonumber(split("/", var.operator_cidr)[1]) >= 32 : tonumber(split("/", var.operator_cidr)[1]) > 8
    )
    error_message = "operator_cidr must be a valid CIDR narrower than /8 (IPv4) or at least /32 (IPv6); the ALB is never open to the world (ADR 0004)."
  }
}

variable "api_image" {
  description = "Container image for the api service. Defaults to a placeholder digest; P3-2 replaces this with the private-ECR digest of this repo's placeholder image."
  type        = string
  default     = "placeholder:local"
}

variable "api_command" {
  description = "Container command override for the api service"
  type        = list(string)
  default     = null
}

variable "worker_image" {
  description = "Container image for the optional worker service. null disables the worker service."
  type        = string
  default     = null
}

variable "worker_command" {
  description = "Container command override for the worker service"
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "orbit-infra"
    ManagedBy = "terraform-preview"
  }
}
