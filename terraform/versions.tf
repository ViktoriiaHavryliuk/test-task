terraform {
  required_version = ">= 1.10.0" # S3 backend native locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state for the real rollout. Left out of the POC so it runs with
  # local state; uncomment and fill in before the team shares the code.
  # Locking uses the S3 lock file (Terraform >= 1.10); no DynamoDB table.
  #
  # backend "s3" {
  #   bucket       = "cde-terraform-state"
  #   key          = "cde-poc/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "pci-cde-poc"
      Scope     = "CDE"
      ManagedBy = "terraform"
    }
  }
}
