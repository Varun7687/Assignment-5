resource "aws_key_pair" "this" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key
  tags       = merge(local.tags.shared, { Name = var.ssh_key_name })
}

resource "aws_instance" "bastion" {
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }
  depends_on = [aws_route_table_association.public, aws_route.public_default, aws_security_group_rule.bastion_ssh]
  ami                         = local.amazon_linux_ami_id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.this["shared-public-a"].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  user_data                   = templatefile("${path.module}/scripts/bastion-user-data.sh.tftpl", { admin_users = var.bastion_admin_users })
  user_data_replace_on_change = true
  metadata_options {
    http_tokens = "required"
  }
  tags = merge(local.tags.shared, { Name = "${local.name}-bastion" })
}

resource "aws_launch_template" "prod" {
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted             = true
      volume_type           = "gp3"
      volume_size           = 8
      delete_on_termination = true
    }
  }
  name_prefix            = "${local.name}-prod-app-"
  image_id               = local.amazon_linux_ami_id
  instance_type          = var.app_instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = base64encode(local.app_user_data)
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }
  metadata_options {
    http_tokens = "required"
  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags.prod, { Name = "${local.name}-prod-app", Role = "application" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags.prod, { Name = "${local.name}-prod-app-root" })
  }
}

resource "aws_lb" "prod" {
  name               = "${local.name}-prod-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.this["prod-public-a"].id, aws_subnet.this["prod-public-b"].id]
  tags               = merge(local.tags.prod, { Name = "${local.name}-prod-alb" })
}

resource "aws_lb_target_group" "prod" {
  name        = "${local.name}-prod-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this["prod"].id
  target_type = "instance"
  health_check {
    path    = "/health"
    matcher = "200"
  }
  tags = merge(local.tags.prod, { Name = "${local.name}-prod-tg" })
}

resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.prod.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod.arn
  }
}

resource "aws_autoscaling_group" "prod" {
  name                      = "${local.name}-prod-asg"
  min_size                  = 2
  max_size                  = 2
  desired_capacity          = 2
  health_check_type         = "ELB"
  health_check_grace_period = 600
  vpc_zone_identifier       = [aws_subnet.this["prod-private-a"].id, aws_subnet.this["prod-private-b"].id]
  target_group_arns         = [aws_lb_target_group.prod.arn]
  launch_template {
    id      = aws_launch_template.prod.id
    version = aws_launch_template.prod.latest_version
  }
  dynamic "tag" {
    for_each = merge(local.tags.prod, { Name = "${local.name}-prod-app" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  depends_on = [
    aws_route53_record.db_prod, aws_route53_zone_association.prod,
    aws_secretsmanager_secret_version.db, aws_iam_role_policy.app_secret_read,
    aws_route.private_default, aws_route_table_association.private,
    aws_route_table_association.public, aws_route.public_default,
    aws_security_group_rule.app_http, aws_security_group_rule.db_from_app,
    aws_lb_listener.prod
  ]
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
  }
}

resource "aws_instance" "dev" {
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }
  ami                    = local.amazon_linux_ami_id
  instance_type          = var.dev_instance_type
  subnet_id              = aws_subnet.this["dev-private-a"].id
  vpc_security_group_ids = [aws_security_group.dev.id]
  key_name               = aws_key_pair.this.key_name
  user_data              = file("${path.module}/scripts/dev-user-data.sh")
  metadata_options {
    http_tokens = "required"
  }
  tags = merge(local.tags.dev, { Name = "${local.name}-dev01" })
}

resource "aws_ami_from_instance" "dev_baseline" {
  # Captures an OS baseline; this does not assert application/cloud-init readiness.

  name                    = "${local.name}-dev-baseline"
  source_instance_id      = aws_instance.dev.id
  snapshot_without_reboot = true
  tags                    = merge(local.tags.dev, { Name = "${local.name}-dev-baseline", BackupType = "AMI" })
}

resource "aws_instance" "backup" {
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }
  depends_on = [
    aws_route53_record.db_prod, aws_route53_zone_association.prod,
    aws_secretsmanager_secret_version.db, aws_secretsmanager_secret_version.master,
    aws_iam_role_policy.backup, aws_route.private_default,
    aws_route_table_association.private, aws_security_group_rule.db_from_backup
  ]
  ami                    = local.amazon_linux_ami_id
  instance_type          = var.backup_instance_type
  subnet_id              = aws_subnet.this["prod-private-a"].id
  vpc_security_group_ids = [aws_security_group.backup.id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = aws_iam_instance_profile.backup.name
  user_data              = templatefile("${path.module}/scripts/backup-user-data.sh.tftpl", { db_host = "db.prod.bluefin.internal", db_secret_arn = aws_secretsmanager_secret.db.arn, backup_bucket = aws_s3_bucket.backups.bucket, sns_topic_arn = aws_sns_topic.operations.arn, master_secret_arn = aws_secretsmanager_secret.master.arn, aws_region = var.aws_region, bootstrap_py = file("${path.module}/scripts/bootstrap-db.py"), backup_py = file("${path.module}/scripts/db-backup.py") })
  metadata_options {
    http_tokens = "required"
  }
  tags = merge(local.tags.prod, { Name = "${local.name}-backup" })
}
