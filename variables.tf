variable "env" {
  type        = string
  description = "Environment name (e.g., dev, prod)."
}

variable "vpc_name" {
  type        = string
  description = "Human-friendly VPC name in tags."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC."
}

variable "public_cidr_blocks" {
  type        = list(string)
  description = "List of CIDRs for public subnets."
}

variable "private_cidr_blocks" {
  type        = list(string)
  description = "List of CIDRs for private subnets."
}

variable "default_tags" {
  type        = map(string)
  description = "Map of default tags for all resources."
  default     = {}
}
