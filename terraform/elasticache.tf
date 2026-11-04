# ---------------------------------
# AWS ElastiCache
# ---------------------------------

resource "aws_elasticache_subnet_group" "hydroserver" {
  name       = "hs-${var.environment}"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_replication_group" "hydroserver" {
  replication_group_id = "hs-${var.environment}"
  description          = "HydroServer cache and Celery broker - ${var.environment}"

  engine             = var.elasticache_engine
  engine_version     = var.elasticache_engine_version
  node_type          = var.elasticache_node_type
  num_cache_clusters = 1
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.hydroserver.name
  security_group_ids = [aws_security_group.elasticache.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  automatic_failover_enabled = false
  apply_immediately          = true
}
