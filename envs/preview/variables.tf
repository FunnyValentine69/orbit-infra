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
}

# Validated and required now so `make plan` fails fast; consumed by the
# ALB module added in a later phase-2 module (P2-2+).
# tflint-ignore: terraform_unused_declarations
variable "operator_cidr" {
  description = "CIDR allowed to reach the ALB"
  type        = string

  validation {
    condition     = can(cidrhost(var.operator_cidr, 0))
    error_message = "operator_cidr must be a valid CIDR block."
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
