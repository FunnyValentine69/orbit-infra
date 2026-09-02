variable "name" {
  description = "Project/resource name prefix"
  type        = string
  default     = "orbit-infra-79s5rw"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub owner login"
  type        = string
  default     = "FunnyValentine69"
}

variable "github_owner_id" {
  description = "GitHub owner immutable numeric ID"
  type        = number
  default     = 185004810
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "orbit-infra"
}

variable "github_repo_id" {
  description = "GitHub repository immutable numeric ID"
  type        = number
  default     = 1354995040
}

variable "oidc_provider_external" {
  description = "Set true when the GitHub OIDC provider already exists in this account (referenced as a data source instead of created)"
  type        = bool
  default     = false
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 20
}

variable "budget_email" {
  description = "Email address to notify on budget alerts"
  type        = string
  sensitive   = true
}

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

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "orbit-infra"
    ManagedBy = "terraform-bootstrap"
  }
}
