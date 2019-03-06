variable "aws_access_key_id" {}
variable "aws_secret_key" {}
variable "region" { default = "us-west-1" }

variable "domain" {  }
variable "subdomain" { }
variable "cdnSubDomain" { }
variable "zoneId" { }
variable "project" { default = "hosting" }

provider "aws" {
  alias = "prod"

  region = "${var.region}"
  access_key = "${var.aws_access_key_id}"
  secret_key = "${var.aws_secret_key}"
}

resource "aws_s3_bucket" "website_bucket" {
  provider = "aws.prod"

  bucket = "${var.subdomain}"
  acl = "public-read"
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[{
    "Sid":"PublicReadForGetBucketObjects",
        "Effect":"Allow",
      "Principal": "*",
      "Action":"s3:GetObject",
      "Resource":["arn:aws:s3:::${var.subdomain}/*"
      ]
    }
  ]
}
POLICY

  website {
    index_document = "index.html"
    error_document = "404.html"
  }
  tags {
    project = "${var.project}"
  }
}

resource "aws_route53_record" "website_route53_record" {
  provider = "aws.prod"
  zone_id = "${var.zoneId}"
  name = "${var.subdomain}"
  type = "A"

  alias {
    name = "${aws_s3_bucket.website_bucket.website_domain}"
    zone_id = "${aws_s3_bucket.website_bucket.hosted_zone_id}"
    evaluate_target_health = false
  }

}

resource "aws_cloudfront_distribution" "cdn" {
  provider = "aws.prod"
  depends_on = ["aws_s3_bucket.website_bucket"]
  origin {
    domain_name = "${var.subdomain}.s3.amazonaws.com"
    origin_id = "website_bucket_origin"
    s3_origin_config {
      origin_access_identity = ""
    }
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["${var.subdomain}"]
  price_class = "PriceClass_100"
  retain_on_delete = true
  default_cache_behavior {
    allowed_methods = [ "DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT" ]
    cached_methods = [ "GET", "HEAD" ]
    target_origin_id = "website_bucket_origin"
    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags {
    project = "${var.project}"
  }
}

resource "aws_route53_record" "route53_to_cdn" {
  provider = "aws.prod"
  zone_id = "${var.zoneId}"
  name = "${var.cdnSubDomain}"
  type = "A"

  alias {
    name = "${aws_cloudfront_distribution.cdn.domain_name}"
    zone_id = "${aws_cloudfront_distribution.cdn.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate" cert {
  domain_name       = "${var.subdomain}"
  validation_method = "DNS"

  tags {
    project = "${var.project}"
  }

  lifecycle {
    create_before_destroy = true
  }

}
