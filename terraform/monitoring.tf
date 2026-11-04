# ---------------------------------
# AWS CloudWatch — Shared Locals
# ---------------------------------

locals {
  notification_email_list = [for e in split(",", var.notification_emails) : trimspace(e) if trimspace(e) != ""]
  uptime_in_main_region   = var.aws_region == "us-east-1"
  uptime_topic_arn        = local.uptime_in_main_region ? aws_sns_topic.hydroserver_alerts.arn : aws_sns_topic.hydroserver_uptime_alerts[0].arn

  monitored_ecs_services = {
    web       = aws_ecs_service.hydroserver_web_service.name
    worker    = aws_ecs_service.hydroserver_worker.name
    scheduler = aws_ecs_service.hydroserver_scheduler.name
  }

  rds_memory_bytes  = data.aws_ec2_instance_type.rds.memory_size * 1024 * 1024
  rds_storage_bytes = var.rds_allocated_storage * 1024 * 1024 * 1024

  rds_utilization_alarms = {
    cpu = {
      metric      = "CPUUtilization"
      comparison  = "GreaterThanThreshold"
      threshold   = var.alert_cpu_utilization_threshold * 100
      description = "CPU utilization"
    }
    memory = {
      metric      = "FreeableMemory"
      comparison  = "LessThanThreshold"
      threshold   = (1 - var.alert_memory_utilization_threshold) * local.rds_memory_bytes
      description = "memory utilization"
    }
    disk = {
      metric      = "FreeStorageSpace"
      comparison  = "LessThanThreshold"
      threshold   = (1 - var.alert_disk_utilization_threshold) * local.rds_storage_bytes
      description = "disk utilization"
    }
  }
}

data "aws_ec2_instance_type" "rds" {
  instance_type = trimprefix(var.rds_instance_class, "db.")
}


# ---------------------------------
# AWS SNS — Notification Topics
# ---------------------------------

resource "aws_sns_topic" "hydroserver_alerts" {
  name = "hs-${var.environment}-alerts"
}

resource "aws_sns_topic_policy" "hydroserver_alerts" {
  arn = aws_sns_topic.hydroserver_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.hydroserver_alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.aws_account_id }
        }
      },
      {
        Sid       = "AllowCloudWatchPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.hydroserver_alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.aws_account_id }
        }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "hydroserver_alerts_email" {
  for_each  = toset(local.notification_email_list)
  topic_arn = aws_sns_topic.hydroserver_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Route 53 health check metrics are only published in us-east-1, so the uptime alarm and its topic live there.
resource "aws_sns_topic" "hydroserver_uptime_alerts" {
  count  = local.uptime_in_main_region ? 0 : 1
  region = "us-east-1"
  name   = "hs-${var.environment}-uptime-alerts"
}

resource "aws_sns_topic_subscription" "hydroserver_uptime_alerts_email" {
  for_each  = local.uptime_in_main_region ? toset([]) : toset(local.notification_email_list)
  region    = "us-east-1"
  topic_arn = aws_sns_topic.hydroserver_uptime_alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}


# ---------------------------------
# AWS CloudWatch — Uptime Monitoring
# ---------------------------------

resource "aws_route53_health_check" "hydroserver_web_uptime" {
  fqdn              = local.proxy_host
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  enable_sni        = true
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name = "hs-${var.environment}-web-uptime"
  }
}

resource "aws_cloudwatch_metric_alarm" "hydroserver_web_uptime_alert" {
  region              = "us-east-1"
  alarm_name          = "hs-${var.environment}-web-uptime-alert"
  alarm_description   = "The HydroServer web/API service for the ${var.environment} environment is failing uptime checks."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.hydroserver_web_uptime.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [local.uptime_topic_arn]
  ok_actions          = [local.uptime_topic_arn]
}


# ---------------------------------
# AWS CloudWatch — API Monitoring
# ---------------------------------

resource "aws_cloudwatch_metric_alarm" "hydroserver_web_5xx_alert" {
  alarm_name          = "hs-${var.environment}-web-5xx-rate"
  alarm_description   = "HydroServer web service (${var.environment}) is returning a sustained elevated rate of HTTP 5xx responses."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alert_5xx_threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.hydroserver_alerts.arn]
  ok_actions          = [aws_sns_topic.hydroserver_alerts.arn]

  metric_query {
    id          = "rate"
    expression  = "(FILL(target, 0) + FILL(lb, 0)) / 300"
    label       = "5xx responses per second"
    return_data = true
  }

  metric_query {
    id = "target"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.hydroserver.arn_suffix
        TargetGroup  = aws_lb_target_group.hydroserver_web.arn_suffix
      }
    }
  }

  metric_query {
    id = "lb"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.hydroserver.arn_suffix
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "hydroserver_web_4xx_alert" {
  alarm_name          = "hs-${var.environment}-web-4xx-rate"
  alarm_description   = "HydroServer web service (${var.environment}) is returning a sustained elevated rate of HTTP 4xx responses."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alert_4xx_threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.hydroserver_alerts.arn]
  ok_actions          = [aws_sns_topic.hydroserver_alerts.arn]

  metric_query {
    id          = "rate"
    expression  = "FILL(target, 0) / 300"
    label       = "4xx responses per second"
    return_data = true
  }

  metric_query {
    id = "target"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_4XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.hydroserver.arn_suffix
        TargetGroup  = aws_lb_target_group.hydroserver_web.arn_suffix
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "hydroserver_web_latency_alert" {
  alarm_name          = "hs-${var.environment}-web-latency"
  alarm_description   = "HydroServer web service (${var.environment}) p99 request latency has been sustained above ${var.alert_latency_threshold_ms}ms."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p99"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alert_latency_threshold_ms / 1000
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.hydroserver_alerts.arn]
  ok_actions          = [aws_sns_topic.hydroserver_alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.hydroserver.arn_suffix
    TargetGroup  = aws_lb_target_group.hydroserver_web.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "hydroserver_ecs_cpu_alert" {
  for_each            = local.monitored_ecs_services
  alarm_name          = "hs-${var.environment}-${each.key}-cpu-utilization"
  alarm_description   = "HydroServer ${each.key} service (${var.environment}) CPU utilization has been sustained above the configured threshold."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alert_cpu_utilization_threshold * 100
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.hydroserver_alerts.arn]
  ok_actions          = [aws_sns_topic.hydroserver_alerts.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.hydroserver.name
    ServiceName = each.value
  }
}

resource "aws_cloudwatch_metric_alarm" "hydroserver_ecs_memory_alert" {
  for_each            = local.monitored_ecs_services
  alarm_name          = "hs-${var.environment}-${each.key}-memory-utilization"
  alarm_description   = "HydroServer ${each.key} service (${var.environment}) memory utilization has been sustained above the configured threshold."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alert_memory_utilization_threshold * 100
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.hydroserver_alerts.arn]
  ok_actions          = [aws_sns_topic.hydroserver_alerts.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.hydroserver.name
    ServiceName = each.value
  }
}


# ---------------------------------
# AWS CloudWatch — Database Monitoring
# ---------------------------------

resource "aws_cloudwatch_metric_alarm" "hydroserver_database_utilization_alert" {
  for_each            = local.rds_utilization_alarms
  alarm_name          = "hs-${var.environment}-database-${each.key}-utilization"
  alarm_description   = "HydroServer database (${var.environment}) ${each.value.description} has been sustained above the configured threshold."
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.hydroserver_alerts.arn]
  ok_actions          = [aws_sns_topic.hydroserver_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.hydroserver.identifier
  }
}

# NOTE: RDS has no instance-state or backup-status metric, so availability problems and backup
# failures are detected from RDS events instead. Validate these patterns against real events after
# the first apply. The backup failure pattern relies on the event message wording, which AWS doesn't
# document precisely.
resource "aws_cloudwatch_event_rule" "hydroserver_database_unavailable" {
  name        = "hs-${var.environment}-database-unavailable"
  description = "HydroServer database instance (${var.environment}) failure or availability events."

  event_pattern = jsonencode({
    source        = ["aws.rds"]
    "detail-type" = ["RDS DB Instance Event"]
    detail = {
      SourceIdentifier = [aws_db_instance.hydroserver.identifier]
      EventCategories  = ["failure", "availability"]
    }
  })
}

resource "aws_cloudwatch_event_target" "hydroserver_database_unavailable" {
  rule = aws_cloudwatch_event_rule.hydroserver_database_unavailable.name
  arn  = aws_sns_topic.hydroserver_alerts.arn
}

resource "aws_cloudwatch_event_rule" "hydroserver_database_backup_failure" {
  name        = "hs-${var.environment}-database-backup-failure"
  description = "A backup failure was reported for the HydroServer database (${var.environment})."

  event_pattern = jsonencode({
    source        = ["aws.rds"]
    "detail-type" = ["RDS DB Instance Event"]
    detail = {
      SourceIdentifier = [aws_db_instance.hydroserver.identifier]
      EventCategories  = ["backup"]
      Message          = [{ wildcard = "*fail*" }, { wildcard = "*Fail*" }]
    }
  })
}

resource "aws_cloudwatch_event_target" "hydroserver_database_backup_failure" {
  rule = aws_cloudwatch_event_rule.hydroserver_database_backup_failure.name
  arn  = aws_sns_topic.hydroserver_alerts.arn
}
