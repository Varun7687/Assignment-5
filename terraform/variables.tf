variable "expected_account_id" {
  type        = string
  description = "Mentor-approved AWS account. Provider refuses a different account."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Supply a 12-digit approved AWS account ID."
  }
}
variable "aws_region" {
  type        = string
  description = "Mentor-approved deployment region, not the SSO login region."
}
variable "availability_zones" {
  type        = list(string)
  description = "Exactly two distinct standard AZs, confirmed available in this account/region."
  validation {
    condition = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2 && alltrue([
      for az in var.availability_zones : can(regex("^${var.aws_region}[a-z]$", az))
    ])
    error_message = "Supply two distinct zones belonging to aws_region."
  }
}
variable "ami_id" {
  type        = string
  description = "Approved Amazon Linux 2023 x86_64 AMI ID in aws_region. No lookup is performed."
  validation {
    condition     = can(regex("^ami-([0-9a-f]{8}|[0-9a-f]{17})$", var.ami_id))
    error_message = "Supply an AMI ID, not an AMI name."
  }
}
variable "ami_region" {
  type        = string
  description = "Region where you independently verified ami_id. This is a consistency check, not AWS verification."
  validation {
    condition     = var.ami_region == var.aws_region
    error_message = "ami_region must match aws_region. Obtain a different AMI when changing region."
  }
}
variable "project_name" {
  type    = string
  default = "bluefin-landing-zone"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,22}$", var.project_name))
    error_message = "Use 3-23 lowercase letters, digits or hyphens, starting with a letter."
  }
}
variable "owner" {
  type = string
}
variable "admin_cidr" {
  type        = string
  description = "Your current public IPv4 address with /32, for SSH only."
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Use your public IPv4 address followed by /32. Do not open SSH globally."
  }
}
variable "ssh_public_key" {
  type = string
  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+) ", var.ssh_public_key))
    error_message = "Supply an SSH PUBLIC key, never a private key."
  }
}
variable "ssh_key_name" {
  type    = string
  default = "bluefin-assignment-5"
}
variable "bastion_admin_users" {
  type        = map(string)
  description = "One Linux username per admin and its SSH public key. Prefer separate keys."
  validation {
    condition = length(var.bastion_admin_users) >= 1 && alltrue([
      for name, key in var.bastion_admin_users : can(regex("^[a-z_][a-z0-9_-]{0,30}$", name)) && !contains(["root", "ec2-user"], name) && can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+) ", key)) && !strcontains(key, "'") && !strcontains(key, "\n")
    ])
    error_message = "Use non-root Linux usernames with valid SSH public keys."
  }
}
variable "notification_emails" {
  type    = list(string)
  default = []
}
variable "db_username" {
  type    = string
  default = "bluefinadmin"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,15}$", var.db_username)) && var.db_username != "bluefinapp"
    error_message = "Use 1-16 alphanumeric characters beginning with a letter; do not use bluefinapp."
  }
}
variable "db_password" {
  type        = string
  sensitive   = true
  description = "NEW unique RDS master password. It is stored in Terraform state; protect the state."
  validation {
    condition = length(var.db_password) >= 16 && length(var.db_password) <= 41 && !strcontains(var.db_password, "REPLACE") && !strcontains(var.db_password, "\"") && !strcontains(var.db_password, "@") && !strcontains(var.db_password, "/") && !strcontains(var.db_password, " ") && can(regex("^[!-~]+$", var.db_password))
    error_message = "Use a new 16-41 character printable ASCII password without spaces, /, @ or double quotes."
  }
}
variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.bastion_instance_type)
    error_message = "Use an x86 micro instance for this lab."
  }
}
variable "app_instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.app_instance_type)
    error_message = "Use an x86 micro instance for this lab."
  }
}
variable "backup_instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.backup_instance_type)
    error_message = "Use an x86 micro instance for this lab."
  }
}
variable "dev_instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.dev_instance_type)
    error_message = "Use an x86 micro instance for this lab."
  }
}
variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "rds_engine_version" {
  type        = string
  default     = null
  description = "Optional supported MySQL version. Null uses the regional default; verify support/cost before apply."
}
variable "rds_backup_retention_days" {
  type    = number
  default = 7
  validation {
    condition     = var.rds_backup_retention_days >= 1 && var.rds_backup_retention_days <= 7
    error_message = "Use 1-7 days."
  }
}
variable "enable_peering_exercise" {
  type    = bool
  default = true
}
variable "enable_peering_routes" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_peering_routes || var.enable_peering_exercise
    error_message = "Peering routes require enable_peering_exercise=true."
  }
}
variable "app_user_data_override" {
  type        = string
  default     = ""
  description = "Optional full replacement user data for your actual Assignment 4 application. Must listen on 8080 and implement /health."
}
variable "force_destroy_buckets" {
  type        = bool
  default     = false
  description = "False protects non-empty backup/audit buckets. Set true only after explicit approval to delete all contents/versions."
}
