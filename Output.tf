output "vpc_id" {
  description = "ID of the VPC created by this module"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "List of IDs for public subnets"
  value       = aws_subnet.public_subnet[*].id
}

output "private_subnet_id" {
  description = "List of IDs for private subnets"
  value       = aws_subnet.private_subnet[*].id
}