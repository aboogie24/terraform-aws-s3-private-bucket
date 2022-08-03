data "aws_iam_account_alias" "current" { 
  count = var.use_account_alias_prefix ? 1 : 0
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {} 

locals { 
  bucket_prefix = var.use_account_alias_prefix 
  bucket_id     = "${local.bucket_prefix}${var.bucket}"
  enable_bucket_logging = var.logging_bucket != "" 
}

data "aws_iam_policy_document" "supplemental_policy" { 

  source_policy_documents = length(var.custom_bucket_policy) > 0 ? [var.custom_bucket_policy] : null 
  
  
  # Enable and Enforce SSL/TLS on all transmitted objects 
  #
  statement {
    sid = "enforce-tls-request-only"
    effect = "Deny"
    principals { 
      type = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_id}/*"
    ]
    condition {
      test = "Bool"
      variable = "aws:SecureTransport"
      values = ["false"]
    }
  }

  statement { 
    sid = "inventory-and-analytics"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["s3.amazonaws.com"]   
    }

    actions = ["s3:PutObject"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_id}/*"
    ]
    condition {
      test = "ArnLike"
      variable = "aws:SourceArn"
      values = ["arn:${data.aws_partition.current.partition}:s3:::${local.bucket.id}"]
    }

    condition {
      test = "StringEquals"
      variable = "aws:SourceAccount"
      values = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test = "StringEquals"
      variable = "s3:x-amz-acl"
      values = ["bucket-owner-full-control"]
    }

  
  }

}

resource "aws_s3_bucket" "private_bucket" {
  bucket = local.bucket_id
  bucket_prefix = var.use_random_suffix ? local.bucket_id : null 
  acl = "private"
  tags = var.tags 
  force_destroy = var.bucket_force_destroy 

  lifecycle {
    ignore_changes = [ 
      policy, 
      versioning, 
      acl, 
      grant, 
      cors_rule,
      lifecycle_rule, 
      logging, 
      server_side_encryption_configuration,
    ]
  }
}

resource "aws_s3_bucket_policy" "private_bucket" {
  bucket = aws_s3_bucket.private_bucket.id
  policy = data.aws_iam_policy_document.supplemental_policy.json
}

resource "aws_s3_bucket_acl" "private_bucket" {
  bucket = aws_s3_bucket.private_bucket.id 
  acl = "private"
}

resource "aws_s3_bucket_versioning" "private_bucket" {
  bucket = aws_s3_bucket.private_bucket.id 

  versioning_configuration { 
    status = var.versioning_status 
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "private_bucket" {
  bucket = aws_s3_bucket.private_bucket.id 

  rule  {
    id = "abort-incomplete-multipart-upload"
    status = "Enabled"

    abort_incomplete_multipart_upload { 
      days_after_initiation = var.abort_incomplete_multipart_upload_days 
    }
  }
}