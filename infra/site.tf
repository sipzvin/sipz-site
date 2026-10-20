data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------------------------------- bucket
resource "aws_s3_bucket" "site" {
  bucket = "${replace(var.domain, ".", "-")}-site-${data.aws_caller_identity.current.account_id}"
}

# Private. Only CloudFront can read it, and only through the origin access control below.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning makes a bad deploy undoable: the previous files are still there.
resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }
  }
  depends_on = [aws_s3_bucket_versioning.site]
}

# ---------------------------------------------------------------------------------------------------------------- CloudFront
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${replace(var.domain, ".", "-")}-site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Only this distribution may read the bucket, and refuse any request that is not over TLS.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "CloudFrontReadsSite"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.bucket.json
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# The site loads nothing from anywhere else and runs no scripts at all, so the policy can be strict: no scripts, no frames,
# no third parties. If a third-party script is ever added, this is the line that will correctly refuse it until it is allowed here.
resource "aws_cloudfront_response_headers_policy" "site" {
  name = "${replace(var.domain, ".", "-")}-site"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    content_security_policy {
      content_security_policy = "default-src 'none'; img-src 'self' data:; style-src 'self'; script-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
      override                = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=()"
      override = true
    }
  }
}

# Send www to the bare domain, so there is one address for the site (and one for search engines to index).
resource "aws_cloudfront_function" "redirect_www" {
  name    = "${replace(var.domain, ".", "-")}-redirect-www"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var r = event.request;
      var host = r.headers.host && r.headers.host.value;
      if (host === 'www.${var.domain}') {
        return { statusCode: 301, statusDescription: 'Moved Permanently', headers: { location: { value: 'https://${var.domain}' + r.uri } } };
      }
      // /privacy -> /privacy.html, and / -> /index.html is handled by the default root object
      if (r.uri.length > 1 && r.uri.indexOf('.') === -1) { r.uri = r.uri.replace(/\/$/, '') + '.html'; }
      return r;
    }
  JS
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.domain
  default_root_object = "index.html"
  aliases             = [var.domain, "www.${var.domain}"]
  price_class         = var.price_class
  http_version        = "http2and3"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id
    # AWS managed "CachingOptimized"
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_www.arn
    }
  }

  # S3 answers 403 for a missing key when the caller cannot list the bucket. Show the real 404 page, with the right status.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ---------------------------------------------------------------------------------------------------------------- DNS
resource "aws_route53_record" "apex" {
  for_each = toset(["A", "AAAA"])
  zone_id  = local.zone_id
  name     = var.domain
  type     = each.value

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  for_each = toset(["A", "AAAA"])
  zone_id  = local.zone_id
  name     = "www.${var.domain}"
  type     = each.value

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
