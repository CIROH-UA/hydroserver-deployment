# ---------------------------------
# AWS VPC
# ---------------------------------

locals {
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "hydroserver" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "hs-${var.environment}"
  }
}

resource "aws_internet_gateway" "hydroserver" {
  vpc_id = aws_vpc.hydroserver.id

  tags = {
    Name = "hs-${var.environment}"
  }
}


# ---------------------------------
# Public Subnets (ECS tasks)
# ---------------------------------

resource "aws_subnet" "public" {
  count             = length(local.availability_zones)
  vpc_id            = aws_vpc.hydroserver.id
  availability_zone = local.availability_zones[count.index]
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, count.index)

  tags = {
    Name = "hs-${var.environment}-public-${local.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.hydroserver.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hydroserver.id
  }

  tags = {
    Name = "hs-${var.environment}-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


# ---------------------------------
# Private Subnets (ALB, RDS, ElastiCache)
# ---------------------------------

resource "aws_subnet" "private" {
  count             = length(local.availability_zones)
  vpc_id            = aws_vpc.hydroserver.id
  availability_zone = local.availability_zones[count.index]
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, count.index + 10)

  tags = {
    Name = "hs-${var.environment}-private-${local.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.hydroserver.id

  tags = {
    Name = "hs-${var.environment}-private"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


# ---------------------------------
# Security Groups
# ---------------------------------

data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "hs-${var.environment}-alb"
  description = "HydroServer load balancer - ${var.environment}"
  vpc_id      = aws_vpc.hydroserver.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
}

resource "aws_security_group" "ecs" {
  name        = "hs-${var.environment}-ecs"
  description = "HydroServer ECS tasks - ${var.environment}"
  vpc_id      = aws_vpc.hydroserver.id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "rds" {
  name        = "hs-${var.environment}-rds"
  description = "HydroServer database - ${var.environment}"
  vpc_id      = aws_vpc.hydroserver.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_security_group" "elasticache" {
  name        = "hs-${var.environment}-elasticache"
  description = "HydroServer cache and task queue - ${var.environment}"
  vpc_id      = aws_vpc.hydroserver.id
}

resource "aws_vpc_security_group_ingress_rule" "elasticache_from_ecs" {
  security_group_id            = aws_security_group.elasticache.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}
