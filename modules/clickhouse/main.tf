module "service" {
  source = "../ecs-service"

  providers = {
    aws = aws
  }

  name        = var.name
  env_id      = var.env_id
  enabled     = var.enabled
  cluster_arn = var.cluster_arn
  image       = var.image

  container_port = 8123
  cpu            = var.cpu
  memory         = var.memory

  env = {
    CLICKHOUSE_DB   = var.database
    CLICKHOUSE_USER = var.user
  }

  secrets = {
    CLICKHOUSE_PASSWORD = var.password_secret_arn
  }

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  permissions_boundary_arn = var.permissions_boundary_arn

  cloud_map_namespace_id     = var.cloud_map_namespace_id
  register_service_discovery = var.register_service_discovery

  health_check = {
    command      = ["CMD-SHELL", "wget -qO- http://127.0.0.1:8123/ping | grep -q Ok"]
    start_period = 30
  }

  tags = var.tags
}
