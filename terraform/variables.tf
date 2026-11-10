# Inputs that differ per deployment. Everything the approved POC design
# fixes (name, VPC CIDR, egress domains, app port, instance sizes) lives in
# locals.tf so that changing it is a reviewed code change.

variable "region" {
  description = "AWS region for the CDE."
  type        = string
  default     = "eu-central-1"
}

variable "availability_zones" {
  description = "AZs to deploy into; one subnet of every tier per AZ. A single AZ halves firewall and NAT cost for the POC."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

# PCI DSS 1.3.1 — inbound
variable "allowed_client_cidrs" {
  description = "Finite list of client IP ranges allowed to reach the ALB on 443."
  type        = list(string)

  validation {
    condition     = length(var.allowed_client_cidrs) > 0 && !contains(var.allowed_client_cidrs, "0.0.0.0/0")
    error_message = "allowed_client_cidrs must be a non-empty list and must not contain 0.0.0.0/0."
  }
}

variable "acm_certificate_arn" {
  description = "ARN of the existing ACM certificate attached to the ALB HTTPS listener."
  type        = string
}

# Database
variable "db_ami_id" {
  description = "Pre-baked AMI for the MySQL instance: MariaDB/MySQL installed and enabled. The data tier has no package source at boot."
  type        = string

  validation {
    condition     = startswith(var.db_ami_id, "ami-")
    error_message = "db_ami_id must be an AMI id (ami-...)."
  }
}

# Application
variable "app_package_url" {
  description = "URL on example.com of the package the app instance installs at boot. The application does not start without it."
  type        = string

  validation {
    condition     = startswith(var.app_package_url, "https://")
    error_message = "app_package_url must be an https:// URL; the firewall only allows TLS egress."
  }
}
