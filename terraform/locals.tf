data "aws_caller_identity" "current" {}

locals {
  name                = var.project_name
  az1                 = var.availability_zones[0]
  az2                 = var.availability_zones[1]
  amazon_linux_ami_id = var.ami_id

  vpcs = {
    shared = { cidr = "10.50.0.0/16", env = "shared" }
    prod   = { cidr = "10.60.0.0/16", env = "prod" }
    dev    = { cidr = "10.70.0.0/16", env = "dev" }
  }

  subnets = {
    "shared-public-a"  = { vpc = "shared", role = "public", az = local.az1, cidr = "10.50.0.0/24" }
    "shared-public-b"  = { vpc = "shared", role = "public", az = local.az2, cidr = "10.50.1.0/24" }
    "shared-private-a" = { vpc = "shared", role = "private", az = local.az1, cidr = "10.50.10.0/24" }
    "shared-private-b" = { vpc = "shared", role = "private", az = local.az2, cidr = "10.50.11.0/24" }
    "prod-public-a"    = { vpc = "prod", role = "public", az = local.az1, cidr = "10.60.0.0/24" }
    "prod-public-b"    = { vpc = "prod", role = "public", az = local.az2, cidr = "10.60.1.0/24" }
    "prod-private-a"   = { vpc = "prod", role = "private", az = local.az1, cidr = "10.60.10.0/24" }
    "prod-private-b"   = { vpc = "prod", role = "private", az = local.az2, cidr = "10.60.11.0/24" }
    "prod-db-a"        = { vpc = "prod", role = "db", az = local.az1, cidr = "10.60.20.0/24" }
    "prod-db-b"        = { vpc = "prod", role = "db", az = local.az2, cidr = "10.60.21.0/24" }
    "dev-private-a"    = { vpc = "dev", role = "private", az = local.az1, cidr = "10.70.10.0/24" }
    "dev-private-b"    = { vpc = "dev", role = "private", az = local.az2, cidr = "10.70.11.0/24" }
    "dev-db-a"         = { vpc = "dev", role = "db", az = local.az1, cidr = "10.70.20.0/24" }
    "dev-db-b"         = { vpc = "dev", role = "db", az = local.az2, cidr = "10.70.21.0/24" }
  }

  common                 = { Project = var.project_name, Owner = var.owner }
  tags                   = { for k, v in local.vpcs : k => merge(local.common, { Environment = v.env }) }
  peering_routes_enabled = var.enable_peering_routes && var.enable_peering_exercise
  app_user_data          = var.app_user_data_override != "" ? var.app_user_data_override : templatefile("${path.module}/scripts/app-user-data.sh.tftpl", { db_host = "db.prod.bluefin.internal", db_secret_arn = aws_secretsmanager_secret.db.arn, aws_region = var.aws_region, app_py = file("${path.module}/../app.py"), index_html = file("${path.module}/../templates/index.html"), requirements_txt = file("${path.module}/../requirements.txt") })
}
