# =============================================================================
# Remote Workstation - EFS One Zone Filesystem
# =============================================================================

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# EFS filesystem — One Zone in the same AZ as the ECS host
# ---------------------------------------------------------------------------
resource "aws_efs_file_system" "devcontainer" {
  creation_token = "${var.project_name}-${var.environment}-devcontainer"

  availability_zone_name = var.availability_zone

  encrypted = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-devcontainer"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Mount target in the host's subnet (same AZ)
# ---------------------------------------------------------------------------
resource "aws_efs_mount_target" "devcontainer" {
  file_system_id  = aws_efs_file_system.devcontainer.id
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.efs.id]
}

# ---------------------------------------------------------------------------
# Security group for EFS mount target
# ---------------------------------------------------------------------------
resource "aws_security_group" "efs" {
  name        = "${var.project_name}-${var.environment}-efs-devcontainer"
  description = "Allow NFS inbound from ECS host to EFS devcontainer mount"
  vpc_id      = data.aws_vpc.host_vpc.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-efs-devcontainer"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nfs_from_host" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = var.security_group_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS from ECS host to EFS"
}

data "aws_vpc" "host_vpc" {
  id = data.aws_subnet.host_subnet.vpc_id
}

data "aws_subnet" "host_subnet" {
  id = var.subnet_id
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "efs_file_system_id" {
  description = "EFS filesystem ID"
  value       = aws_efs_file_system.devcontainer.id
}

output "efs_dns_name" {
  description = "EFS DNS mount target (use this in /etc/fstab)"
  value       = aws_efs_file_system.devcontainer.dns_name
}

output "efs_mount_target_ip" {
  description = "EFS mount target IP address"
  value       = aws_efs_mount_target.devcontainer.ip_address
}

output "efs_arn" {
  description = "EFS filesystem ARN"
  value       = aws_efs_file_system.devcontainer.arn
}
