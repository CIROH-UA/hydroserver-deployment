terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      "hydroserver:environment" = var.environment
      "hydroserver:managed-by"  = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}


# ---------------------------------
# AWS Environment Configuration
# ---------------------------------

variable "environment" {
  description = "The name of the HydroServer environment (prod, test, dev)"
  type        = string
}

variable "aws_account_id" {
  description = "The AWS account ID this HydroServer instance will be deployed in."
  type        = string
}

variable "aws_region" {
  description = "The AWS region this HydroServer instance will be deployed in."
  type        = string
}

variable "hydroserver_version" {
  description = "The HydroServer release tag to deploy (e.g. v1.5.0)."
  type        = string

  validation {
    condition     = trimspace(var.hydroserver_version) != "" && lower(var.hydroserver_version) != "latest"
    error_message = "Set HYDROSERVER_VERSION to a specific HydroServer release tag, such as v1.5.0. 'latest' isn't allowed."
  }
}

variable "prevent_data_deletion" {
  description = "Controls whether the RDS database and media bucket will be protected from deletion."
  type        = bool
  default     = true
}

variable "prevent_service_deletion" {
  description = "Controls whether the load balancer and static bucket will be protected from deletion."
  type        = bool
  default     = true
}

variable "public_access_enabled" {
  description = "Controls whether the CloudFront distribution is enabled and allowed to read the static and media buckets."
  type        = bool
  default     = false
}

variable "iam_permissions_boundary_arn" {
  description = "The ARN of an IAM permissions boundary to attach to the IAM roles Terraform creates. Leave empty for none."
  type        = string
  default     = ""
}


# ---------------------------------
# AWS RDS Configuration
# ---------------------------------

variable "rds_engine_version" {
  description = "The PostgreSQL version deployed by RDS."
  type        = string
  default     = "17"
}

variable "rds_instance_class" {
  description = "The instance class used by RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "The size of the RDS database disk, in gigabytes."
  type        = number
  default     = 20

  validation {
    condition     = var.rds_allocated_storage >= 20
    error_message = "RDS_ALLOCATED_STORAGE must be at least 20."
  }
}

variable "rds_backup_enabled" {
  description = "Controls whether RDS will create automated database backups."
  type        = bool
  default     = true
}

variable "rds_backup_count" {
  description = "The number of days RDS will retain automated backups."
  type        = number
  default     = 14

  validation {
    condition     = var.rds_backup_count >= 1 && var.rds_backup_count <= 35
    error_message = "RDS_BACKUP_COUNT must be between 1 and 35."
  }
}

variable "rds_restore_snapshot_identifier" {
  description = "Snapshot the RDS instance is restored from when it is replaced. Only set by the stage data workflow."
  type        = string
  default     = ""
}


# ---------------------------------
# AWS ECS Configuration
# ---------------------------------

variable "proxy_base_url" {
  description = "The base URL HydroServer will be served from."
  type        = string
}

variable "smtp_url" {
  description = "The SMTP URL HydroServer will use."
  type        = string
  default     = "smtp://127.0.0.1:1025"
  sensitive   = true
}

variable "api_rate_limits" {
  description = "Controls HydroServer's API rate limits. Set to False to disable rate limiting, or a JSON object to override specific per-view rate limits."
  type        = string
  default     = "False"
}

variable "account_rate_limits" {
  description = "Controls HydroServer's account rate limits. Set to False to disable rate limiting, or a JSON object to override specific per-view rate limits."
  type        = string
  default     = "False"
}

variable "gunicorn_workers" {
  description = "The number of gunicorn workers to spawn per web service container."
  type        = number
  default     = 3

  validation {
    condition     = var.gunicorn_workers >= 1 && floor(var.gunicorn_workers) == var.gunicorn_workers
    error_message = "GUNICORN_WORKERS must be a whole number of at least 1."
  }
}

variable "gunicorn_threads" {
  description = "The number of threads each gunicorn worker uses to handle requests."
  type        = number
  default     = 4

  validation {
    condition     = var.gunicorn_threads >= 1 && floor(var.gunicorn_threads) == var.gunicorn_threads
    error_message = "GUNICORN_THREADS must be a whole number of at least 1."
  }
}

variable "debug_enabled" {
  description = "Enables debug mode in Django. Should be disabled in production."
  type        = string
  default     = "False"
}

variable "auto_email" {
  description = "The email address account management emails will be sent from."
  type        = string
  default     = "no-reply@127.0.0.1:1025"
}

variable "account_signup_enabled" {
  description = "Allows new users to create HydroServer accounts."
  type        = string
  default     = "True"
}

variable "account_ownership_enabled" {
  description = "Allows new users to create and own workspaces."
  type        = string
  default     = "True"
}

variable "socialaccount_signup_only" {
  description = "Only allows social signup methods."
  type        = string
  default     = "False"
}

variable "csrf_trusted_origins" {
  description = "Allows trusted origins to authenticate with HydroServer's APIs."
  type        = string
  default     = ""
}

variable "allowed_hosts" {
  description = "A comma-separated list of host/domain names HydroServer is allowed to serve."
  type        = string
  default     = ""
}

variable "noindex_enabled" {
  description = "Tells search engines not to index HydroServer when set to True."
  type        = string
  default     = "False"
}

variable "session_cookie_name" {
  description = "The name of HydroServer's session cookie."
  type        = string
  default     = "hs_session"
}

variable "service_account_email_domain" {
  description = "The email domain used for HydroServer's auto-generated service account emails."
  type        = string
  default     = "hydroserver.local"
}

variable "log_format" {
  description = "The format HydroServer emits application logs in."
  type        = string
  default     = "json"
}

variable "log_retention_days" {
  description = "The number of days CloudWatch keeps HydroServer container and WAF logs."
  type        = number
  default     = 30
}

variable "idp_oidc_enabled" {
  description = "Enables HydroServer OIDC identity provider feature."
  type        = string
  default     = "False"
}

variable "media_storage_enabled" {
  description = "Enables media file storage in HydroServer."
  type        = string
  default     = "True"
}

variable "ecs_web_cpu" {
  description = "The number of vCPUs to assign to each web service container."
  type        = number
  default     = 1
}

variable "ecs_web_memory" {
  description = "The amount of memory (GB) to assign to each web service container."
  type        = number
  default     = 2
}

variable "ecs_web_min_count" {
  description = "The minimum number of web service containers ECS will run."
  type        = number
  default     = 1
}

variable "ecs_web_max_count" {
  description = "The maximum number of web service containers ECS will run."
  type        = number
  default     = 1
}

variable "ecs_web_cpu_target" {
  description = "The average CPU utilization (percent) ECS scales the web service to keep."
  type        = number
  default     = 60
}

variable "ecs_worker_cpu" {
  description = "The number of vCPUs to assign to each Celery worker container."
  type        = number
  default     = 1
}

variable "ecs_worker_memory" {
  description = "The amount of memory (GB) to assign to each Celery worker container."
  type        = number
  default     = 2
}

variable "ecs_worker_count" {
  description = "The number of Celery worker containers ECS will run."
  type        = number
  default     = 1

  validation {
    condition     = var.ecs_worker_count >= 1 && floor(var.ecs_worker_count) == var.ecs_worker_count
    error_message = "ECS_WORKER_COUNT must be a whole number of at least 1."
  }
}

variable "celery_worker_concurrency" {
  description = "The number of tasks each Celery worker container runs at once."
  type        = number
  default     = 2

  validation {
    condition     = var.celery_worker_concurrency >= 1 && floor(var.celery_worker_concurrency) == var.celery_worker_concurrency
    error_message = "CELERY_WORKER_CONCURRENCY must be a whole number of at least 1."
  }
}

variable "ecs_scheduler_cpu" {
  description = "The number of vCPUs to assign to the Celery scheduler container."
  type        = number
  default     = 1
}

variable "ecs_scheduler_memory" {
  description = "The amount of memory (GB) to assign to the Celery scheduler container."
  type        = number
  default     = 2
}

variable "ecs_init_cpu" {
  description = "The number of vCPUs to assign to the initialization management container."
  type        = number
  default     = 1
}

variable "ecs_init_memory" {
  description = "The amount of memory (GB) to assign to the initialization management container."
  type        = number
  default     = 2
}


# ---------------------------------
# AWS ElastiCache Configuration
# ---------------------------------

variable "elasticache_engine" {
  description = "The ElastiCache engine to use (valkey or redis)."
  type        = string
  default     = "valkey"
}

variable "elasticache_engine_version" {
  description = "The version of the ElastiCache engine to use."
  type        = string
  default     = "8.0"
}

variable "elasticache_node_type" {
  description = "The ElastiCache node type to use."
  type        = string
  default     = "cache.t4g.micro"
}


# ---------------------------------
# AWS CloudWatch Configuration
# ---------------------------------

variable "notification_emails" {
  description = "Comma-separated list of email addresses that will receive CloudWatch alarm notifications."
  type        = string
  default     = ""
}

variable "alert_5xx_threshold" {
  description = "The rate (requests/second, sustained over 5 minutes) of HTTP 5xx responses from the web service that will trigger an alert."
  type        = number
  default     = 1
}

variable "alert_4xx_threshold" {
  description = "The rate (requests/second, sustained over 5 minutes) of HTTP 4xx responses from the web service that will trigger an alert."
  type        = number
  default     = 20
}

variable "alert_latency_threshold_ms" {
  description = "The p99 request latency (in milliseconds) that will trigger an alert."
  type        = number
  default     = 3000
}

variable "alert_cpu_utilization_threshold" {
  description = "The CPU utilization (as a fraction of 1.0) that will trigger an alert for ECS and RDS."
  type        = number
  default     = 0.8
}

variable "alert_memory_utilization_threshold" {
  description = "The memory utilization (as a fraction of 1.0) that will trigger an alert for ECS and RDS."
  type        = number
  default     = 0.8
}

variable "alert_disk_utilization_threshold" {
  description = "The disk utilization (as a fraction of 1.0) that will trigger an alert for RDS."
  type        = number
  default     = 0.8
}


# ---------------------------------
# AWS CloudFront Configuration
# ---------------------------------

variable "web_service_timeout" {
  description = "The time (in seconds) CloudFront waits for a response from the web service."
  type        = number
  default     = 30
}

variable "cloudfront_certificate_arn" {
  description = "The ARN of the us-east-1 ACM certificate CloudFront will use."
  type        = string
}

variable "alb_certificate_arn" {
  description = "The ARN of the ACM certificate the load balancer will use. Required when aws_region isn't us-east-1."
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "The CloudFront price class, which limits the edge locations used."
  type        = string
  default     = "PriceClass_100"
}


# ---------------------------------
# AWS WAF Configuration
# ---------------------------------

variable "waf_rate_limit" {
  description = "The number of requests per minute a single client IP can send to the web service before WAF returns 429."
  type        = number
  default     = 1000

  validation {
    condition     = var.waf_rate_limit >= 10 && floor(var.waf_rate_limit) == var.waf_rate_limit
    error_message = "WAF_RATE_LIMIT must be a whole number of at least 10."
  }
}

variable "waf_auth_rate_limit" {
  description = "The number of account POST requests per minute a single client IP can send before WAF returns 429."
  type        = number
  default     = 30

  validation {
    condition     = var.waf_auth_rate_limit >= 10 && floor(var.waf_auth_rate_limit) == var.waf_auth_rate_limit
    error_message = "WAF_AUTH_RATE_LIMIT must be a whole number of at least 10."
  }
}

variable "waf_throttle_enabled" {
  description = "Throttles clients over WAF's general rate limit. When false, WAF only counts the requests it would throttle."
  type        = bool
  default     = true
}

variable "waf_auth_throttle_enabled" {
  description = "Throttles clients over WAF's account endpoint rate limit. When false, WAF only counts the requests it would throttle."
  type        = bool
  default     = true
}

variable "waf_rules_enabled" {
  description = "Blocks requests that match WAF's managed rules. When false, WAF only counts the requests it would block."
  type        = bool
  default     = true
}
