# =============================================================================
# Terraform Configuration - AWS Provider
# =============================================================================
# This configures Terraform to use AWS as the cloud provider.
# Region is configurable via variables.tf (defaults to ap-south-1 / Mumbai).

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
