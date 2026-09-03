output "vpc_id" {
  description = "ID of the preview VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the preview VPC"
  value       = module.network.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.network.public_subnet_ids
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.network.private_subnet_id
}

output "private_route_table_id" {
  description = "ID of the private subnet's route table"
  value       = module.network.private_route_table_id
}

output "endpoint_sg_id" {
  description = "ID of the security group attached to the VPC interface endpoints"
  value       = module.network.endpoint_sg_id
}

output "azs" {
  description = "Availability zones used by this environment's VPC"
  value       = module.network.azs
}

output "ecs_cluster_arn" {
  description = "ARN of the preview environment's ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "api_service_name" {
  description = "Name of the api ECS service"
  value       = module.api.service_name
}

output "api_task_definition_arn" {
  description = "ARN of the applied api ECS task definition"
  value       = module.api.task_definition_arn
}

output "worker_service_name" {
  description = "Name of the worker ECS service"
  value       = module.worker.service_name
}

output "worker_task_definition_arn" {
  description = "ARN of the applied worker ECS task definition, or null when disabled"
  value       = module.worker.task_definition_arn
}

output "redis_service_name" {
  description = "Name of the Redis ECS service"
  value       = module.redis.service_name
}

output "redis_task_definition_arn" {
  description = "ARN of the applied Redis ECS task definition"
  value       = module.redis.task_definition_arn
}

output "clickhouse_service_name" {
  description = "Name of the ClickHouse ECS service"
  value       = module.clickhouse.service_name
}

output "clickhouse_task_definition_arn" {
  description = "ARN of the applied ClickHouse ECS task definition"
  value       = module.clickhouse.task_definition_arn
}

output "data_bucket_name" {
  description = "Name of the environment's S3 data bucket"
  value       = aws_s3_bucket.data.bucket
}

output "redis_dns_name" {
  description = "Service discovery DNS name for Redis"
  value       = module.redis.discovery_dns_name
}

output "clickhouse_dns_name" {
  description = "Service discovery DNS name for ClickHouse"
  value       = module.clickhouse.discovery_dns_name
}

output "alb_dns_name" {
  description = "DNS name of the environment's ALB"
  value       = aws_lb.this.dns_name
}

output "api_url" {
  description = "HTTP URL for reaching the api service through the ALB"
  value       = "http://${aws_lb.this.dns_name}"
}

output "api_environment_keys" {
  description = "Keys of the merged api service environment (var.api_env plus the fixed keys this root computes); used to assert that user-supplied api_env keys reach the api task"
  value       = keys(local.api_env)
}

output "api_secret_keys" {
  description = "Keys of the api task's ECS `secrets` map (local.api_secrets, passed into module.api); used to assert the ClickHouse password secret reaches the api task"
  value       = keys(local.api_secrets)
}

output "alerts_topic_arn" {
  description = "ARN of the SNS topic that receives CloudWatch alarm notifications"
  value       = aws_sns_topic.alerts.arn
  sensitive   = true
}

output "unhealthy_hosts_alarm_name" {
  description = "Name of the UnHealthyHostCount CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name
}

output "target_5xx_alarm_name" {
  description = "Name of the HTTPCode_Target_5XX_Count CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.target_5xx.alarm_name
}
