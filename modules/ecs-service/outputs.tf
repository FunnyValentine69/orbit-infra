output "service_name" {
  description = "Name of the ECS service, null when var.enabled is false"
  value       = var.enabled ? aws_ecs_service.this[0].name : null
}

output "service_arn" {
  description = "ID/ARN of the ECS service, null when var.enabled is false"
  value       = var.enabled ? aws_ecs_service.this[0].id : null
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition, null when var.enabled is false"
  value       = var.enabled ? aws_ecs_task_definition.this[0].arn : null
}

output "task_role_arn" {
  description = "ARN of the task's IAM role, null when var.enabled is false"
  value       = var.enabled ? aws_iam_role.task[0].arn : null
}

output "execution_role_arn" {
  description = "ARN of the task's execution IAM role, null when var.enabled is false"
  value       = var.enabled ? aws_iam_role.execution[0].arn : null
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for this service, null when var.enabled is false"
  value       = var.enabled ? aws_cloudwatch_log_group.this[0].name : null
}

output "discovery_service_arn" {
  description = "ARN of the Cloud Map service discovery entry, null unless enabled and var.register_service_discovery is true"
  value       = var.enabled && var.register_service_discovery ? aws_service_discovery_service.this[0].arn : null
}
