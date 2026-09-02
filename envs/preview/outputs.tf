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
