output "discovery_dns_name" {
  description = "Service discovery DNS name, computed from var.name and var.namespace_name; null when namespace_name is unset"
  value       = var.namespace_name != null ? "${var.name}.${var.namespace_name}" : null
}

output "port" {
  value = 8123
}

output "service_name" {
  value = module.service.service_name
}
