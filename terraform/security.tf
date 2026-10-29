resource "aws_security_group" "bastion" {
  name        = "${local.name}-bastion-sg"
  description = "Only current admin IPv4 may SSH"
  vpc_id      = aws_vpc.this["shared"].id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags.shared, { Name = "${local.name}-bastion-sg" })
}
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Public HTTP entry point"
  vpc_id      = aws_vpc.this["prod"].id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags.prod, { Name = "${local.name}-alb-sg" })
}
resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "Application tier"
  vpc_id      = aws_vpc.this["prod"].id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags.prod, { Name = "${local.name}-app-sg" })
}
resource "aws_security_group" "backup" {
  name        = "${local.name}-backup-sg"
  description = "Dedicated database backup host"
  vpc_id      = aws_vpc.this["prod"].id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags.prod, { Name = "${local.name}-backup-sg" })
}
resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Private MySQL database"
  vpc_id      = aws_vpc.this["prod"].id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags.prod, { Name = "${local.name}-rds-sg" })
}
resource "aws_security_group" "dev" {
  name        = "${local.name}-dev-sg"
  description = "Private development host"
  vpc_id      = aws_vpc.this["dev"].id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags.dev, { Name = "${local.name}-dev-sg" })
}
resource "aws_security_group_rule" "bastion_ssh" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  security_group_id = aws_security_group.bastion.id
  cidr_blocks = [var.admin_cidr]
}
resource "aws_security_group_rule" "alb_http" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  security_group_id = aws_security_group.alb.id
  cidr_blocks = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "app_http" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 8080
  to_port           = 8080
  security_group_id = aws_security_group.app.id
  source_security_group_id = aws_security_group.alb.id
}
resource "aws_security_group_rule" "app_ssh" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  security_group_id = aws_security_group.app.id
  cidr_blocks = [local.vpcs.shared.cidr]
}
resource "aws_security_group_rule" "backup_ssh" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  security_group_id = aws_security_group.backup.id
  cidr_blocks = [local.vpcs.shared.cidr]
}
resource "aws_security_group_rule" "dev_ssh" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  security_group_id = aws_security_group.dev.id
  cidr_blocks = [local.vpcs.shared.cidr]
}
resource "aws_security_group_rule" "db_from_app" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 3306
  to_port           = 3306
  security_group_id = aws_security_group.rds.id
  source_security_group_id = aws_security_group.app.id
}
resource "aws_security_group_rule" "db_from_backup" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 3306
  to_port           = 3306
  security_group_id = aws_security_group.rds.id
  source_security_group_id = aws_security_group.backup.id
}
