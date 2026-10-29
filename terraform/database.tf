resource "aws_db_subnet_group" "prod" {
  name       = "${local.name}-prod-db-subnets"
  subnet_ids = [aws_subnet.this["prod-db-a"].id, aws_subnet.this["prod-db-b"].id]
  tags       = merge(local.tags.prod, { Name = "${local.name}-prod-db-subnets" })
}

resource "aws_db_instance" "prod" {
  identifier              = "${local.name}-prod-db"
  engine                  = "mysql"
  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_class
  allocated_storage       = 20
  max_allocated_storage   = 50
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = "inventory"
  username                = var.db_username
  password                = var.db_password
  port                    = 3306
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = var.rds_backup_retention_days
  backup_window           = "18:00-18:30"
  maintenance_window      = "sun:19:00-sun:19:30"
  db_subnet_group_name    = aws_db_subnet_group.prod.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  apply_immediately       = true
  tags                    = merge(local.tags.prod, { Name = "${local.name}-prod-db" })
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/prod/database"
  recovery_window_in_days = 7
  tags                    = merge(local.tags.prod, { Name = "${local.name}-prod-db-secret" })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ username = "bluefinapp", password = random_password.app.result, host = "db.prod.bluefin.internal", port = 3306, database = "inventory" })
}

resource "aws_db_event_subscription" "prod" {
  depends_on = [aws_sns_topic_policy.eventbridge]
  name             = "${local.name}-rds-events"
  sns_topic        = aws_sns_topic.operations.arn
  source_type      = "db-instance"
  source_ids       = [aws_db_instance.prod.identifier]
  event_categories = ["backup", "failure", "notification", "configuration change"]
  enabled          = true
  tags             = merge(local.tags.prod, { Name = "${local.name}-rds-events" })
}

resource "random_password" "app" {
  length  = 32
  special = false
}
resource "aws_secretsmanager_secret" "master" {
  name                    = "${local.name}/prod/database-bootstrap"
  recovery_window_in_days = 7
  tags                    = merge(local.tags.prod, { Name = "${local.name}-db-bootstrap-secret" })
}
resource "aws_secretsmanager_secret_version" "master" {
  secret_id     = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({ username = var.db_username, password = var.db_password, host = "db.prod.bluefin.internal", port = 3306, database = "inventory" })
}
