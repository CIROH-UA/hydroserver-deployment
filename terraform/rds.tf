# ---------------------------------
# AWS RDS Database
# ---------------------------------

locals {
  rds_engine_major_version = split(".", var.rds_engine_version)[0]
}

resource "aws_db_subnet_group" "hydroserver" {
  name       = "hs-${var.environment}"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_parameter_group" "hydroserver" {
  name_prefix = "hs-${var.environment}-postgres${local.rds_engine_major_version}-"
  family      = "postgres${local.rds_engine_major_version}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name  = "log_statement"
    value = "ddl"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "hydroserver" {
  identifier     = "hs-${var.environment}"
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage = var.rds_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = local.database_name
  username = local.database_admin_username
  password = local.database_admin_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.hydroserver.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.hydroserver.name
  publicly_accessible    = false

  backup_retention_period = var.rds_backup_enabled ? var.rds_backup_count : 0
  backup_window           = "19:00-19:30"
  maintenance_window      = "sun:20:00-sun:20:30"
  copy_tags_to_snapshot   = true

  deletion_protection       = var.prevent_data_deletion
  skip_final_snapshot       = !var.prevent_data_deletion
  final_snapshot_identifier = "hs-${var.environment}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]
  auto_minor_version_upgrade      = true
  apply_immediately               = true

  snapshot_identifier = var.rds_restore_snapshot_identifier != "" ? var.rds_restore_snapshot_identifier : null

  lifecycle {
    ignore_changes = [snapshot_identifier]
  }
}


# ---------------------------------
# AWS RDS Database Secrets
# ---------------------------------

resource "random_password" "hydroserver_database_user_password" {
  length           = 15
  upper            = true
  min_upper        = 1
  lower            = true
  min_lower        = 1
  numeric          = true
  min_numeric      = 1
  special          = true
  min_special      = 1
  override_special = "-_~*"
}

resource "random_password" "hydroserver_secret_key" {
  length           = 50
  special          = true
  upper            = true
  lower            = true
  numeric          = true
  override_special = "!@#$%^&*()-_=+{}[]|:;\"'<>,.?/"
}

locals {
  database_name           = "hydroserver"
  database_admin_username = "hsdbadmin"
  database_admin_password = "a${random_password.hydroserver_database_user_password.result}"
  database_url            = "postgresql://${local.database_admin_username}:${local.database_admin_password}@${aws_db_instance.hydroserver.address}:${aws_db_instance.hydroserver.port}/${local.database_name}"
}

resource "aws_secretsmanager_secret" "hydroserver_database_url" {
  name                    = "hs-${var.environment}-database-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "hydroserver_database_url_value" {
  secret_id     = aws_secretsmanager_secret.hydroserver_database_url.id
  secret_string = local.database_url
}

resource "aws_secretsmanager_secret" "hydroserver_secret_key" {
  name                    = "hs-${var.environment}-secret-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "hydroserver_secret_key_value" {
  secret_id     = aws_secretsmanager_secret.hydroserver_secret_key.id
  secret_string = random_password.hydroserver_secret_key.result
}

resource "tls_private_key" "hydroserver_idp_oidc" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "hydroserver_idp_oidc_private_key" {
  name                    = "hs-${var.environment}-idp-oidc-private-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "hydroserver_idp_oidc_private_key_value" {
  secret_id     = aws_secretsmanager_secret.hydroserver_idp_oidc_private_key.id
  secret_string = tls_private_key.hydroserver_idp_oidc.private_key_pem_pkcs8
}

resource "aws_secretsmanager_secret" "hydroserver_database_password" {
  name                    = "hs-${var.environment}-database-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "hydroserver_database_password_value" {
  secret_id     = aws_secretsmanager_secret.hydroserver_database_password.id
  secret_string = local.database_admin_password
}
