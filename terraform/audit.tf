resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}-cloudtrail"
  force_destroy = var.force_destroy_buckets
  tags          = merge(local.tags.shared, { Name = "${local.name}-cloudtrail-bucket" })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Sid = "Acl", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:GetBucketAcl", Resource = aws_s3_bucket.cloudtrail.arn }, { Sid = "Write", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*", Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } } }, { Sid = "TLS", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}

resource "aws_cloudtrail" "main" {
  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_s3_bucket_versioning.cloudtrail,
    aws_s3_bucket_server_side_encryption_configuration.cloudtrail,
    aws_s3_bucket_public_access_block.cloudtrail
  ]
  name                          = local.name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true
  tags                          = merge(local.tags.shared, { Name = "${local.name}-trail" })
}

resource "aws_s3_bucket" "backups" {
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}-backups"
  force_destroy = var.force_destroy_buckets
  tags          = merge(local.tags.prod, { Name = "${local.name}-backup-bucket" })
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  depends_on = [aws_s3_bucket_versioning.backups]
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "expire-db-dumps"
    status = "Enabled"
    filter {
      prefix = "db/"
    }
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Sid = "TLS", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}
