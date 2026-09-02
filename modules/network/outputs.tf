output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, one per AZ"
  value       = aws_subnet.public[*].id
}

output "private_subnet_id" {
  description = "ID of the single private subnet"
  value       = aws_subnet.private.id
}

output "private_route_table_id" {
  description = "ID of the private subnet's route table"
  value       = aws_route_table.private.id
}

output "endpoint_sg_id" {
  description = "ID of the security group attached to the VPC interface endpoints"
  value       = aws_security_group.endpoints.id
}

output "azs" {
  description = "Availability zones used by this VPC"
  value       = local.azs
}
