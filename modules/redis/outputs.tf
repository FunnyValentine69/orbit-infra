output "discovery_dns_name" {
  description = "Service discovery DNS name, computed from var.name and var.namespace_name; null when namespace_name is unset"
  value       = var.namespace_name != null ? "${var.name}.${var.namespace_name}" : null
}

output "port" {
  description = "TCP port Redis listens on"
  value       = 6379
}

output "service_name" {
  description = "Name of the underlying ECS service"
  value       = module.service.service_name
}

output "container_definitions_json" {
  description = "The underlying ECS service's task definition container_definitions JSON string"
  value       = module.service.container_definitions_json
}
