module "service" {
  source = "../ecs-service"
  region = var.region

  providers = {
    aws = aws
  }

  name        = var.name
  env_id      = var.env_id
  enabled     = var.enabled
  cluster_arn = var.cluster_arn
  image       = var.image

  command = [
    "redis-server",
    "--appendonly", "no",
    "--maxmemory", "200mb",
    "--maxmemory-policy", "allkeys-lru",
  ]

  container_port = 6379
  cpu            = var.cpu
  memory         = var.memory

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  permissions_boundary_arn = var.permissions_boundary_arn

  cloud_map_namespace_id     = var.cloud_map_namespace_id
  register_service_discovery = var.register_service_discovery

  health_check = {
    command = ["CMD-SHELL", "redis-cli ping | grep PONG"]
  }

  tags = var.tags
}
