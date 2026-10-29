# Credentials come from the AWS SDK chain: environment, named CLI profile or SSO.
# No access keys belong in Terraform source or tfvars.
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
}
