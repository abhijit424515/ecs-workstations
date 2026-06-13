# =============================================================================
# Remote Workstation - Variables
# =============================================================================

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "personal"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "personal-workstation"
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "devcontainer"
}

variable "availability_zone" {
  description = "Availability zone for EFS One Zone (must match ECS host)"
  type        = string
  default     = "ap-south-1a"
}

variable "subnet_id" {
  description = "Subnet ID of the ECS host (for EFS mount target)"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID of the ECS host (for NFS ingress rule)"
  type        = string
}

variable "efs_size_gb" {
  description = "Provisioned size hint (documentation only — EFS is pay-per-use, no provisioning needed)"
  type        = number
  default     = 50
}
