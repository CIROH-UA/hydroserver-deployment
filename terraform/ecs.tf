locals {
  hydroserver_image = "${aws_ecr_repository.hydroserver.repository_url}:${var.hydroserver_version}"
  proxy_host        = replace(replace(var.proxy_base_url, "https://", ""), "http://", "")
  redis_host        = aws_elasticache_replication_group.hydroserver.primary_endpoint_address

  hydroserver_container_defaults = {
    name        = "hydroserver"
    image       = local.hydroserver_image
    essential   = true
    environment = [for k, v in local.hydroserver_app_env : { name = k, value = v }]
    secrets     = [for k, v in local.hydroserver_app_secret_env : { name = k, valueFrom = v }]
  }

  # Memory (GB) Fargate allows for each vCPU size.
  fargate_memory_options = {
    "0.25" = [0.5, 1, 2]
    "0.5"  = range(1, 5)
    "1"    = range(2, 9)
    "2"    = range(4, 17)
    "4"    = range(8, 31)
    "8"    = range(16, 61, 4)
    "16"   = range(32, 121, 8)
  }

  ecs_task_sizes = {
    web       = { cpu = var.ecs_web_cpu, memory = var.ecs_web_memory }
    worker    = { cpu = var.ecs_worker_cpu, memory = var.ecs_worker_memory }
    scheduler = { cpu = var.ecs_scheduler_cpu, memory = var.ecs_scheduler_memory }
    init      = { cpu = var.ecs_init_cpu, memory = var.ecs_init_memory }
  }
}


# ---------------------------------
# AWS ECS Cluster
# ---------------------------------

resource "aws_ecs_cluster" "hydroserver" {
  name = "hs-${var.environment}"
}

resource "aws_cloudwatch_log_group" "hydroserver" {
  name              = "/ecs/hs-${var.environment}"
  retention_in_days = var.log_retention_days
}


# ---------------------------------
# AWS ECS Task Definitions
# ---------------------------------

resource "aws_ecs_task_definition" "hydroserver" {
  for_each = {
    web = merge(local.hydroserver_container_defaults, {
      command      = ["sh", "-c", "gunicorn --bind 0.0.0.0:8000 --workers ${var.gunicorn_workers} --threads ${var.gunicorn_threads} hydroserver.wsgi:application"]
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
    })
    worker = merge(local.hydroserver_container_defaults, {
      command = ["celery", "-A", "hydroserver", "worker", "--loglevel=INFO", "--concurrency=${var.celery_worker_concurrency}"]
    })
    scheduler = merge(local.hydroserver_container_defaults, {
      command = ["celery", "-A", "hydroserver", "beat", "--loglevel=INFO"]
    })
    init = merge(local.hydroserver_container_defaults, {
      command = ["python", "manage.py", "check"]
    })
  }

  family                   = "hs-${each.key}-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(local.ecs_task_sizes[each.key].cpu * 1024)
  memory                   = tostring(local.ecs_task_sizes[each.key].memory * 1024)
  execution_role_arn       = aws_iam_role.hydroserver_ecs_execution.arn
  task_role_arn            = aws_iam_role.hydroserver_ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    merge(each.value, {
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.hydroserver.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = each.key
        }
      }
    })
  ])

  lifecycle {
    precondition {
      condition     = contains(lookup(local.fargate_memory_options, tostring(local.ecs_task_sizes[each.key].cpu), []), local.ecs_task_sizes[each.key].memory)
      error_message = "ECS_${upper(each.key)}_CPU = ${local.ecs_task_sizes[each.key].cpu} and ECS_${upper(each.key)}_MEMORY = ${local.ecs_task_sizes[each.key].memory} isn't a CPU and memory combination Fargate supports. See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html#fargate-tasks-size."
    }
  }

  depends_on = [
    null_resource.ghcr_to_ecr,
    aws_secretsmanager_secret_version.hydroserver_database_url_value,
    aws_secretsmanager_secret_version.hydroserver_secret_key_value,
  ]
}


# ---------------------------------
# AWS ECS Web Service
# ---------------------------------

resource "aws_ecs_service" "hydroserver_web_service" {
  name                              = "hs-web-${var.environment}"
  cluster                           = aws_ecs_cluster.hydroserver.id
  task_definition                   = aws_ecs_task_definition.hydroserver["web"].arn
  launch_type                       = "FARGATE"
  desired_count                     = var.ecs_web_min_count
  health_check_grace_period_seconds = 120
  propagate_tags                    = "SERVICE"
  wait_for_steady_state             = true

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.hydroserver_web.arn
    container_name   = "hydroserver"
    container_port   = 8000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.hydroserver_https,
    aws_db_instance.hydroserver,
  ]
}

resource "aws_appautoscaling_target" "hydroserver_web_service" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.hydroserver.name}/${aws_ecs_service.hydroserver_web_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.ecs_web_min_count
  max_capacity       = var.ecs_web_max_count
}

resource "aws_appautoscaling_policy" "hydroserver_web_service_cpu" {
  name               = "hs-web-${var.environment}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.hydroserver_web_service.service_namespace
  resource_id        = aws_appautoscaling_target.hydroserver_web_service.resource_id
  scalable_dimension = aws_appautoscaling_target.hydroserver_web_service.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.ecs_web_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}


# ---------------------------------
# AWS ECS Celery Worker
# ---------------------------------

resource "aws_ecs_service" "hydroserver_worker" {
  name            = "hs-worker-${var.environment}"
  cluster         = aws_ecs_cluster.hydroserver.id
  task_definition = aws_ecs_task_definition.hydroserver["worker"].arn
  launch_type     = "FARGATE"
  desired_count   = var.ecs_worker_count
  propagate_tags  = "SERVICE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_db_instance.hydroserver]
}


# ---------------------------------
# AWS ECS Celery Scheduler
# ---------------------------------

resource "aws_ecs_service" "hydroserver_scheduler" {
  name            = "hs-scheduler-${var.environment}"
  cluster         = aws_ecs_cluster.hydroserver.id
  task_definition = aws_ecs_task_definition.hydroserver["scheduler"].arn
  launch_type     = "FARGATE"
  desired_count   = 1
  propagate_tags  = "SERVICE"

  # Stop the old scheduler before starting the new one so two never run at once.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_db_instance.hydroserver]
}


# ---------------------------------
# AWS ECS IAM Roles
# ---------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

resource "aws_iam_role" "hydroserver_ecs_execution" {
  name                 = "hs-${var.environment}-ecs-execution"
  description          = "Pulls HydroServer images and reads secrets for ECS - ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_assume_role.json
  permissions_boundary = var.iam_permissions_boundary_arn != "" ? var.iam_permissions_boundary_arn : null
}

resource "aws_iam_role_policy_attachment" "hydroserver_ecs_execution" {
  role       = aws_iam_role.hydroserver_ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "hydroserver_ecs_execution_secrets" {
  name = "secrets"
  role = aws_iam_role.hydroserver_ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = values(local.hydroserver_app_secret_env)
      }
    ]
  })
}

resource "aws_iam_role" "hydroserver_ecs_task" {
  name                 = "hs-${var.environment}-ecs-task"
  description          = "HydroServer application role - ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_assume_role.json
  permissions_boundary = var.iam_permissions_boundary_arn != "" ? var.iam_permissions_boundary_arn : null
}

resource "aws_iam_role_policy" "hydroserver_ecs_task_buckets" {
  name = "buckets"
  role = aws_iam_role.hydroserver_ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.hydroserver_static_bucket.arn,
          aws_s3_bucket.hydroserver_media_bucket.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = concat(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], local.hydroserver_extra_object_actions)
        Resource = [
          "${aws_s3_bucket.hydroserver_static_bucket.arn}/*",
          "${aws_s3_bucket.hydroserver_media_bucket.arn}/*",
        ]
      },
    ]
  })
}


# ---------------------------------
# AWS ECS Service Secrets
# ---------------------------------

resource "aws_secretsmanager_secret" "hydroserver_smtp_url" {
  name                    = "hs-${var.environment}-smtp-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "hydroserver_smtp_url_version" {
  secret_id     = aws_secretsmanager_secret.hydroserver_smtp_url.id
  secret_string = var.smtp_url != "" ? var.smtp_url : "smtp://127.0.0.1:1025"
}
