resource "aws_iam_group" "admins" {
  name = "bluefin-admins"
}

resource "aws_iam_group" "developers" {
  name = "bluefin-developers"
}

resource "aws_iam_policy" "admin_mfa" {
  name   = "${local.name}-admins-mfa-required"
  policy = file("${path.module}/iam/admin-mfa-policy.json")
}

resource "aws_iam_policy" "developer" {
  name   = "${local.name}-developers-scoped"
  policy = file("${path.module}/iam/developer-policy.json")
}

resource "aws_iam_group_policy_attachment" "admins" {
  group      = aws_iam_group.admins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group_policy_attachment" "admins_mfa" {
  group      = aws_iam_group.admins.name
  policy_arn = aws_iam_policy.admin_mfa.arn
}

resource "aws_iam_group_policy_attachment" "developers" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developer.arn
}

resource "aws_iam_user" "admin_test" {
  name = "bluefin-admin-test"
  tags = merge(local.tags.shared, { Name = "bluefin-admin-test" })
}

resource "aws_iam_user" "developer_test" {
  name = "bluefin-developer-test"
  tags = merge(local.tags.dev, { Name = "bluefin-developer-test" })
}

resource "aws_iam_user_group_membership" "admin_test" {
  user   = aws_iam_user.admin_test.name
  groups = [aws_iam_group.admins.name]
}

resource "aws_iam_user_group_membership" "developer_test" {
  user   = aws_iam_user.developer_test.name
  groups = [aws_iam_group.developers.name]
}

resource "aws_iam_role" "app" {
  name               = "${local.name}-app-role"
  assume_role_policy = file("${path.module}/iam/ec2-trust-policy.json")
  tags               = merge(local.tags.prod, { Name = "${local.name}-app-role" })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "app_secret_read" {
  name   = "${local.name}-app-secret-read"
  role   = aws_iam_role.app.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.db.arn }] })
}

resource "aws_iam_role" "backup" {
  name               = "${local.name}-backup-role"
  assume_role_policy = file("${path.module}/iam/ec2-trust-policy.json")
  tags               = merge(local.tags.prod, { Name = "${local.name}-backup-role" })
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_iam_instance_profile" "backup" {
  name = "${local.name}-backup-profile"
  role = aws_iam_role.backup.name
}

resource "aws_iam_role_policy" "backup" {
  name = "${local.name}-backup-policy"
  role = aws_iam_role.backup.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_secretsmanager_secret.db.arn, aws_secretsmanager_secret.master.arn] },
    { Effect = "Allow", Action = ["s3:PutObject", "s3:AbortMultipartUpload"], Resource = "${aws_s3_bucket.backups.arn}/db/*" },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.backups.arn },
    { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.operations.arn }
  ] })
}
