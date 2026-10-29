output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
output "deployment_region" {
  value = var.aws_region
}
output "availability_zones" {
  value = var.availability_zones
}
output "vpc_ids" {
  value = { for name, vpc in aws_vpc.this : name => vpc.id }
}
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
output "dev_private_ip" {
  value = aws_instance.dev.private_ip
}
output "backup_private_ip" {
  value = aws_instance.backup.private_ip
}
output "prod_alb_dns_name" {
  value = aws_lb.prod.dns_name
}
output "prod_alb_url" {
  value = "http://${aws_lb.prod.dns_name}"
}
output "prod_db_private_dns" {
  value = "db.prod.bluefin.internal"
}
output "dev_private_dns" {
  value = "dev01.dev.bluefin.internal"
}
output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}
output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail.bucket
}
output "operations_sns_topic_arn" {
  value = aws_sns_topic.operations.arn
}
output "test_users" {
  value = { admins = aws_iam_user.admin_test.name, developers = aws_iam_user.developer_test.name }
}
