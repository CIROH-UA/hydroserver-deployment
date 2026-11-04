# ---------------------------------
# AWS Internal Load Balancer
# ---------------------------------

locals {
  alb_certificate_arn = var.alb_certificate_arn != "" ? var.alb_certificate_arn : var.cloudfront_certificate_arn
}

resource "aws_lb" "hydroserver" {
  name                       = "hs-${var.environment}"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = aws_subnet.private[*].id
  security_groups            = [aws_security_group.alb.id]
  idle_timeout               = 60
  drop_invalid_header_fields = true
  enable_deletion_protection = var.prevent_service_deletion
}

resource "aws_lb_target_group" "hydroserver_web" {
  name                 = "hs-${var.environment}-web"
  port                 = 8000
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.hydroserver.id
  deregistration_delay = 30

  health_check {
    path                = "/health-check"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "hydroserver_https" {
  load_balancer_arn = aws_lb.hydroserver.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.hydroserver_web.arn
  }

  lifecycle {
    precondition {
      condition     = var.aws_region == "us-east-1" || var.alb_certificate_arn != ""
      error_message = "ALB_CERTIFICATE_ARN is required when AWS_REGION isn't us-east-1. Create an ACM certificate for the HydroServer domain in ${var.aws_region}."
    }
  }
}


# ---------------------------------
# AWS CloudFront Origins
# ---------------------------------

resource "aws_cloudfront_vpc_origin" "hydroserver" {
  vpc_origin_endpoint_config {
    name                   = "hs-${var.environment}"
    arn                    = aws_lb.hydroserver.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

resource "aws_cloudfront_origin_access_control" "hydroserver" {
  name                              = "hs-${var.environment}"
  description                       = "HydroServer static and media buckets - ${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}


# ---------------------------------
# AWS CloudFront Distribution
# ---------------------------------

resource "aws_cloudfront_distribution" "hydroserver" {
  comment         = "HydroServer - ${var.environment}"
  enabled         = var.public_access_enabled
  aliases         = [local.proxy_host]
  price_class     = var.cloudfront_price_class
  http_version    = "http2and3"
  is_ipv6_enabled = true
  web_acl_id      = aws_wafv2_web_acl.hydroserver.arn

  origin {
    origin_id   = "web"
    domain_name = aws_lb.hydroserver.dns_name

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.hydroserver.id
      origin_read_timeout      = var.web_service_timeout
      origin_keepalive_timeout = 5
    }
  }

  origin {
    origin_id                = "static"
    domain_name              = aws_s3_bucket.hydroserver_static_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.hydroserver.id
  }

  origin {
    origin_id                = "media"
    domain_name              = aws_s3_bucket.hydroserver_media_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.hydroserver.id
  }

  default_cache_behavior {
    target_origin_id         = "web"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
    compress                 = true
  }

  dynamic "ordered_cache_behavior" {
    for_each = ["static", "media"]
    content {
      path_pattern           = "/${ordered_cache_behavior.value}/*"
      target_origin_id       = ordered_cache_behavior.value
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
      compress               = true
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

output "cloudfront_domain_name" {
  description = "The CloudFront domain name the HydroServer domain's DNS record should point to."
  value       = aws_cloudfront_distribution.hydroserver.domain_name
}


# ---------------------------------
# AWS WAF Web ACL
# ---------------------------------

locals {
  # CommonRuleSet rules that would block normal HydroServer traffic, such as observation uploads over 8 KB,
  # long SensorThings queries, and sensors that don't send a User-Agent. These only count matching requests.
  waf_common_rule_count_overrides = [
    "SizeRestrictions_BODY",
    "SizeRestrictions_QUERYSTRING",
    "NoUserAgent_HEADER",
    "CrossSiteScripting_BODY",
  ]

  waf_static_paths = ["/static/", "/media/"]
}

resource "aws_wafv2_web_acl" "hydroserver" {
  region      = "us-east-1"
  name        = "hs-${var.environment}-waf"
  description = "WAF web ACL for HydroServer - ${var.environment}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = [
      { priority = 1000, name = "known-bad-inputs", group = "AWSManagedRulesKnownBadInputsRuleSet", count_overrides = [] },
      { priority = 1010, name = "common", group = "AWSManagedRulesCommonRuleSet", count_overrides = local.waf_common_rule_count_overrides },
    ]
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = var.waf_rules_enabled ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = var.waf_rules_enabled ? [] : [1]
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value.group

          dynamic "rule_action_override" {
            for_each = rule.value.count_overrides
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "hs-${var.environment}-${rule.value.name}"
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "account-rate-limit"
    priority = 2000

    action {
      dynamic "block" {
        for_each = var.waf_auth_throttle_enabled ? [1] : []
        content {
          custom_response {
            response_code = 429
          }
        }
      }
      dynamic "count" {
        for_each = var.waf_auth_throttle_enabled ? [] : [1]
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.waf_auth_rate_limit
        evaluation_window_sec = 60
        aggregate_key_type    = "IP"

        scope_down_statement {
          and_statement {
            statement {
              byte_match_statement {
                search_string         = "POST"
                positional_constraint = "EXACTLY"
                field_to_match {
                  method {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              or_statement {
                dynamic "statement" {
                  for_each = ["/accounts/", "/identity/"]
                  content {
                    byte_match_statement {
                      search_string         = statement.value
                      positional_constraint = "STARTS_WITH"
                      field_to_match {
                        uri_path {}
                      }
                      text_transformation {
                        priority = 0
                        type     = "NONE"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "hs-${var.environment}-account-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "general-rate-limit"
    priority = 3000

    action {
      dynamic "block" {
        for_each = var.waf_throttle_enabled ? [1] : []
        content {
          custom_response {
            response_code = 429
          }
        }
      }
      dynamic "count" {
        for_each = var.waf_throttle_enabled ? [] : [1]
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.waf_rate_limit
        evaluation_window_sec = 60
        aggregate_key_type    = "IP"

        scope_down_statement {
          not_statement {
            statement {
              or_statement {
                dynamic "statement" {
                  for_each = local.waf_static_paths
                  content {
                    byte_match_statement {
                      search_string         = statement.value
                      positional_constraint = "STARTS_WITH"
                      field_to_match {
                        uri_path {}
                      }
                      text_transformation {
                        priority = 0
                        type     = "NONE"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "hs-${var.environment}-general-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "hs-${var.environment}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_log_group" "hydroserver_waf" {
  region            = "us-east-1"
  name              = "aws-waf-logs-hs-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_wafv2_web_acl_logging_configuration" "hydroserver" {
  region                  = "us-east-1"
  resource_arn            = aws_wafv2_web_acl.hydroserver.arn
  log_destination_configs = [aws_cloudwatch_log_group.hydroserver_waf.arn]

  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }
      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}
