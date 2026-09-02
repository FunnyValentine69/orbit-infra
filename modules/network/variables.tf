variable "name" {
  description = "Resource name prefix"
  type        = string
}

variable "env_id" {
  description = "Ephemeral environment identifier, applied as the env_id tag on every taggable resource"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.42.0.0/16"
}

variable "azs" {
  description = "Availability zones to use (first = private+public AZ, second = second public AZ). Empty list means: look up the first two AZs in the region."
  type        = list(string)
  default     = []
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints (ecr.api, ecr.dkr, logs, secretsmanager, ssmmessages). LocalStack may not emulate every interface endpoint service."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default     = {}
}
