output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_id" {
  value = module.network.private_subnet_id
}

output "private_route_table_id" {
  value = module.network.private_route_table_id
}

output "endpoint_sg_id" {
  value = module.network.endpoint_sg_id
}

output "azs" {
  value = module.network.azs
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "api_service_name" {
  value = module.api.service_name
}

output "worker_service_name" {
  value = module.worker.service_name
}

output "data_bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "redis_dns_name" {
  value = module.redis.discovery_dns_name
}

output "clickhouse_dns_name" {
  value = module.clickhouse.discovery_dns_name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "api_url" {
  value = "http://${aws_lb.this.dns_name}"
}
