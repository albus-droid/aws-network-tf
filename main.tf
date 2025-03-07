###############################
# Data source: availability zones
###############################
data "aws_availability_zones" "this" {
  state = "available"
}

###############################
# Create VPC
###############################
resource "aws_vpc" "this" {
  cidr_block       = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.default_tags,
    { "Name" = var.vpc_name }
  )
}

###############################
# Optionally create an IGW (only if public subnets enabled)
###############################
resource "aws_internet_gateway" "this" {
  count = var.enable_public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(
    var.default_tags,
    { "Name" = "${var.vpc_name}-igw" }
  )
}

###############################
# Create Public Subnets (2) if enabled
###############################
resource "aws_subnet" "public" {
  count = var.enable_public_subnets ? 2 : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.this.names, count.index)

  # So instances in public subnets automatically get public IPs
  map_public_ip_on_launch = true

  tags = merge(
    var.default_tags,
    { "Name" = "${var.vpc_name}-public-subnet-${count.index}" }
  )
}

###############################
# Create Private Subnets (2)
###############################
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.this.names, count.index)

  map_public_ip_on_launch = false

  tags = merge(
    var.default_tags,
    { "Name" = "${var.vpc_name}-private-subnet-${count.index}" }
  )
}

###############################
# Create NAT Gateway in first public subnet (only if enabled)
###############################
resource "aws_eip" "nat" {
  count = var.enable_public_subnets ? 1 : 0
  vpc   = true

  depends_on = [
    aws_internet_gateway.this
  ]

  tags = merge(
    var.default_tags,
    { "Name" = "${var.vpc_name}-nat-eip" }
  )
}

resource "aws_nat_gateway" "this" {
  count = var.enable_public_subnets ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = length(aws_subnet.public) > 0 ? aws_subnet.public[0].id : null

  depends_on = [
    aws_internet_gateway.this
  ]

  tags = merge(
    var.default_tags,
    { "Name" = "${var.vpc_name}-nat-gw" }
  )
}

###############################
# Create Public Route Table (1) if public subnets are enabled
###############################
resource "aws_route_table" "public" {
  count = var.enable_public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
  }

  tags = merge(
    var.default_tags,
    { "Name" = "${var.vpc_name}-public-rt" }
  )
}

###############################
# Associate Public Subnets to the Public Route Table
###############################
resource "aws_route_table_association" "public_assoc" {
  count = var.enable_public_subnets ? length(aws_subnet.public) : 0

  route_table_id = aws_route_table.public[0].id
  subnet_id      = aws_subnet.public[count.index].id
}

###############################
# Create Private Route Tables (2) if public subnets enabled
# or a single private route table if you prefer
###############################
resource "aws_route_table" "private" {
  count = var.enable_public_subnets ? 2 : 1

  vpc_id = aws_vpc.this.id

  # If public subnets are enabled, route 0.0.0.0/0 -> NAT Gateway
  # Otherwise, do NOT create that route
  dynamic "route" {
    for_each = var.enable_public_subnets ? [true] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = length(aws_nat_gateway.this) > 0 ? aws_nat_gateway.this[0].id : null
    }
  }

  tags = merge(
    var.default_tags,
    { "Name" = "${var.vpc_name}-private-rt-${count.index}" }
  )
}

###############################
# Associate Private Subnets with the Private RT(s)
###############################
resource "aws_route_table_association" "private_assoc" {
  # If we have 2 route tables (i.e. public is enabled), one per subnet
  # else we have only 1 route table, so all subnets share it
  count = 2

  route_table_id = var.enable_public_subnets ? aws_route_table.private[count.index].id : aws_route_table.private[0].id

  subnet_id = aws_subnet.private[count.index].id
}

###############################
# Outputs
###############################
output "vpc_id" {
  description = "The ID of the newly created VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (empty if enable_public_subnets=false)"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_route_table_id" {
  description = "Public route table ID (null if not created)"
  value       = length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
}

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = [for rt in aws_route_table.private : rt.id]
}
