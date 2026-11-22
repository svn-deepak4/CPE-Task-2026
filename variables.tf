variable "project_name" {
  description = "Short prefix used for resource names."
  type        = string
  default     = "cpe-assessment"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 2-20 lowercase letters, numbers, or hyphens, and start and end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,8}[a-z0-9]$", var.environment))
    error_message = "environment must be 2-10 lowercase letters, numbers, or hyphens, and start and end with a letter or number."
  }
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  description = "CIDR range for the VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition = can(cidrnetmask(var.vpc_cidr)) && try(
      tonumber(split("/", var.vpc_cidr)[1]) >= 8 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 20,
      false
    )
    error_message = "vpc_cidr must be an IPv4 CIDR with a prefix between /8 and /20 so two usable private subnets can be created."
  }
}

variable "allowed_client_cidrs" {
  description = "CIDR ranges permitted to connect to the internal ALB. Defaults to the VPC only."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_client_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every allowed_client_cidrs entry must be a valid IPv4 CIDR block."
  }
}

variable "tags" {
  description = "Additional tags applied to resources."
  type        = map(string)
  default     = {}
}
