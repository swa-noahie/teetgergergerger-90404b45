# S3 static website hosting (no CloudFront). Requires AWS S3 Block Public Access
# to allow bucket policies that grant public read.

resource "aws_s3_bucket" "ui" {
  bucket        = "luv-teetgergergerger-9de1c5a8-ui"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "ui_own" {
  bucket = aws_s3_bucket.ui.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "ui_bpa" {
  bucket = aws_s3_bucket.ui.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "ui_site" {
  bucket = aws_s3_bucket.ui.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "index.html"
  }
}

data "aws_iam_policy_document" "ui_public" {
  statement {
    sid     = "AllowPublicRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.ui.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "ui_public" {
  bucket     = aws_s3_bucket.ui.id
  policy     = data.aws_iam_policy_document.ui_public.json
  depends_on = [aws_s3_bucket_public_access_block.ui_bpa]
}

resource "aws_s3_bucket_cors_configuration" "ui_cors" {
  bucket = aws_s3_bucket.ui.id
  cors_rule {
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 300
  }
}

# --------- Outputs ---------
output "ui_bucket_name" {
  value = aws_s3_bucket.ui.bucket
}

# Hostname only (no scheme). Example: bucket.s3-website-us-east-1.amazonaws.com
output "ui_website_endpoint" {
  value = aws_s3_bucket_website_configuration.ui_site.website_endpoint
}