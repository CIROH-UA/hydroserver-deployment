# ---------------------------------
# Static Bucket
# ---------------------------------

resource "aws_s3_bucket" "hydroserver_static_bucket" {
  bucket        = "hs-static-${var.environment}-${var.aws_account_id}"
  force_destroy = var.prevent_service_deletion ? false : true
}

resource "aws_s3_bucket_ownership_controls" "hydroserver_static_bucket" {
  bucket = aws_s3_bucket.hydroserver_static_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "hydroserver_static_bucket" {
  bucket                  = aws_s3_bucket.hydroserver_static_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "hydroserver_static_bucket_cloudfront_access" {
  count  = var.public_access_enabled ? 1 : 0
  bucket = aws_s3_bucket.hydroserver_static_bucket.id
  policy = data.aws_iam_policy_document.cloudfront_bucket_access["static"].json

  depends_on = [aws_s3_bucket_public_access_block.hydroserver_static_bucket]
}


# ---------------------------------
# Media Bucket
# ---------------------------------

resource "aws_s3_bucket" "hydroserver_media_bucket" {
  bucket        = "hs-media-${var.environment}-${var.aws_account_id}"
  force_destroy = var.prevent_data_deletion ? false : true
}

resource "aws_s3_bucket_ownership_controls" "hydroserver_media_bucket" {
  bucket = aws_s3_bucket.hydroserver_media_bucket.id

  rule {
    object_ownership = local.hydroserver_media_object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "hydroserver_media_bucket" {
  bucket                  = aws_s3_bucket.hydroserver_media_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "hydroserver_media_bucket_cloudfront_access" {
  count  = var.public_access_enabled ? 1 : 0
  bucket = aws_s3_bucket.hydroserver_media_bucket.id
  policy = data.aws_iam_policy_document.cloudfront_bucket_access["media"].json

  depends_on = [aws_s3_bucket_public_access_block.hydroserver_media_bucket]
}


# ---------------------------------
# CloudFront Bucket Access
# ---------------------------------

data "aws_iam_policy_document" "cloudfront_bucket_access" {
  for_each = {
    static = aws_s3_bucket.hydroserver_static_bucket.arn
    media  = aws_s3_bucket.hydroserver_media_bucket.arn
  }

  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${each.value}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.hydroserver.arn]
    }
  }
}
