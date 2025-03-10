# Terraform Config file (main.tf). This has provider block (AWS) and config for provisioning one EC2 instance resource.  

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.27"
    }
  }

  required_version = ">=0.14"
}
provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# Data source for availability zones in us-east-1
data "aws_availability_zones" "available" {
  state = "available"
}

# Define tags locally
locals {
  default_tags = merge(var.default_tags, { "env" = var.env })
}

# Create a new VPC 
resource "aws_vpc" "main" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"
  tags = merge(
    local.default_tags, {
      Name = var.env
    }
  )
}

# Add provisioning of the public subnetin the default VPC
resource "aws_subnet" "public_subnet" {
  count             = length(var.public_cidr_blocks)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_cidr_blocks[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = merge(
    local.default_tags, {
      Name = "${var.env}-public-subnet-${count.index}"
    }
  )
}

resource "aws_subnet" "private_subnet" {
  count      = length(var.private_cidr_blocks)
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_cidr_blocks[count.index]

  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = merge(
    var.default_tags,
    { Name = "${var.vpc_name}-private-${count.index}" }
  )
}
# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  count  = length(var.public_cidr_blocks) > 0 ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = merge(local.default_tags,
    {
      "Name" = "${var.env}-igw"
    }
  )
}

###############################
# 5. NAT Gateway in the first public subnet (only if we have public subnets)
###############################
resource "aws_eip" "nat" {
  count      = length(var.public_cidr_blocks) > 0 ? 1 : 0
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "ngw" {
  count = length(var.public_cidr_blocks) > 0 ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = length(aws_subnet.public_subnet) > 0 ? aws_subnet.public_subnet[0].id : null

  depends_on = [aws_internet_gateway.igw]

  tags = merge(
    var.default_tags,
    { Name = "${var.vpc_name}-nat" }
  )
}
# Route table to route add default gateway pointing to Internet Gateway (IGW)
resource "aws_route_table" "public_subnets" {
  count = length(var.public_cidr_blocks) > 0 ? 1 : 0
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
  tags = {
    Name = "${var.env}-route-public-subnets"
  }
}

# Associate subnets with the custom route table
resource "aws_route_table_association" "public_route_table_association" {
  count = length(var.public_cidr_blocks) > 0 ? 1 : 0
  route_table_id = aws_route_table.public_subnets.id
  subnet_id      = aws_subnet.public_subnet[count.index].id
}

###############################
# 8. Route tables for private subnets
###############################
# We'll create one private route table per private subnet, each routing 0.0.0.0/0 to NAT if public subnets exist
resource "aws_route_table" "private" {
  count  = length(var.private_cidr_blocks)
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = length(var.public_cidr_blocks) > 0 ? [true] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = length(aws_nat_gateway.ngw) > 0 ? aws_nat_gateway.ngw[0].id : null
    }
  }

  tags = merge(
    var.default_tags,
    { Name = "${var.vpc_name}-private-rt-${count.index}" }
  )
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.public_subnet[*].id)
  route_table_id = aws_route_table.private[count.index].id
  subnet_id      = aws_subnet.private_subnet[count.index].id
}
