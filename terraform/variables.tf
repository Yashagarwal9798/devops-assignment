# =============================================================================
# Variables - Configurable Parameters
# =============================================================================
# All tunables are defined here. Override via terraform.tfvars or -var flags.

variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "ap-south-1" # Mumbai — closest to India
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "iii-inference"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "inference_instance_type" {
  description = "Instance type for inference worker (needs ~8GB RAM for the model)"
  type        = string
  default     = "t3.large" # 8GB RAM, 2 vCPU — cheapest option for 8GB
}

variable "caller_instance_type" {
  description = "Instance type for caller worker (lightweight TypeScript)"
  type        = string
  default     = "t3.micro" # 1GB RAM, 2 vCPU — free tier eligible
}

variable "api_instance_type" {
  description = "Instance type for API gateway (Nginx reverse proxy)"
  type        = string
  default     = "t3.micro" # 1GB RAM, 2 vCPU — free tier eligible
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "devops-assignment-key"
}
