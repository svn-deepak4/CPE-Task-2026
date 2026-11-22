resource "aws_kms_key" "runtime_config" {
  description             = "Encrypts the ${local.name} runtime parameter."
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = {
    Name = "${local.name}-runtime-config"
  }
}

resource "aws_kms_alias" "runtime_config" {
  name          = "alias/${local.name}-runtime-config"
  target_key_id = aws_kms_key.runtime_config.key_id
}

resource "aws_ssm_parameter" "runtime_config" {
  name        = "/${local.name}/runtime-config"
  description = "Non-secret Lambda runtime settings."
  type        = "SecureString"
  key_id      = aws_kms_key.runtime_config.arn
  value = jsonencode({
    max_message_length = 10000
  })

  tags = {
    Name = "${local.name}-runtime-config"
  }
}

resource "aws_s3_bucket" "mtls" {
  bucket        = "${substr(var.project_name, 0, 12)}-${var.environment}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-mtls"
  force_destroy = true

  tags = {
    Name = "${local.name}-mtls"
  }
}

resource "aws_s3_bucket_public_access_block" "mtls" {
  bucket                  = aws_s3_bucket.mtls.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "mtls" {
  bucket = aws_s3_bucket.mtls.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mtls" {
  bucket = aws_s3_bucket.mtls.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "mtls" {
  bucket = aws_s3_bucket.mtls.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.mtls.arn,
          "${aws_s3_bucket.mtls.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "AllowLoadBalancerReadCaBundle"
        Effect    = "Allow"
        Principal = { Service = "elasticloadbalancing.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.mtls.arn}/ca/ca.pem"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.mtls]
}

resource "aws_s3_object" "ca_bundle" {
  bucket       = aws_s3_bucket.mtls.id
  key          = "ca/ca.pem"
  content      = tls_self_signed_cert.ca.cert_pem
  content_type = "application/x-pem-file"
}

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${substr(var.project_name, 0, 12)}-${var.environment}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-alb-logs"
  force_destroy = false

  tags = {
    Name = "${local.name}-alb-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-alb-logs-after-30-days"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowALBLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.alb_logs.arn}/alb/access/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
          "${aws_s3_bucket.alb_logs.arn}/alb/connection/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.alb_logs.arn,
          "${aws_s3_bucket.alb_logs.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
