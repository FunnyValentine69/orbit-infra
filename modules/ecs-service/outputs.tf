output "service_name" {
  value = var.enabled ? aws_ecs_service.this[0].name : null
}

output "service_arn" {
  value = var.enabled ? aws_ecs_service.this[0].id : null
}

output "task_definition_arn" {
  value = var.enabled ? aws_ecs_task_definition.this[0].arn : null
}

output "task_role_arn" {
  value = var.enabled ? aws_iam_role.task[0].arn : null
}

output "execution_role_arn" {
  value = var.enabled ? aws_iam_role.execution[0].arn : null
}

output "log_group_name" {
  value = var.enabled ? aws_cloudwatch_log_group.this[0].name : null
}

output "discovery_service_arn" {
  value = var.enabled && var.register_service_discovery ? aws_service_discovery_service.this[0].arn : null
}
