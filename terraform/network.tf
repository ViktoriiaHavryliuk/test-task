############################################################################
# network.tf — VPC, subnets, internet gateway, NAT gateways
#
# Five subnet tiers, one subnet per tier per AZ:
#   alb       public   Application Load Balancer only
#   nat       public   NAT gateway only
#   firewall  private  Network Firewall endpoint only
#   app       private  app instance(s)
#   data      private  MySQL instance
#
# Nothing gets a public IP at launch. The ALB and NAT gateways are the only
# resources with public addresses.
############################################################################

locals {
  az_index = { for i, az in var.availability_zones : az => i }

  # /24 per subnet. Offsets keep the plan readable:
  # alb 10.0.0-1, nat 10.0.2-3, firewall 10.0.4-5, app 10.0.10-11, data 10.0.20-21
  subnet_cidrs = {
    alb      = { for az, i in local.az_index : az => cidrsubnet(local.vpc_cidr, 8, 0 + i) }
    nat      = { for az, i in local.az_index : az => cidrsubnet(local.vpc_cidr, 8, 2 + i) }
    firewall = { for az, i in local.az_index : az => cidrsubnet(local.vpc_cidr, 8, 4 + i) }
    app      = { for az, i in local.az_index : az => cidrsubnet(local.vpc_cidr, 8, 10 + i) }
    data     = { for az, i in local.az_index : az => cidrsubnet(local.vpc_cidr, 8, 20 + i) }
  }
}

resource "aws_vpc" "cde" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_subnet" "alb" {
  for_each                = local.subnet_cidrs.alb
  vpc_id                  = aws_vpc.cde.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-alb-${each.key}", Tier = "alb" }
}

resource "aws_subnet" "nat" {
  for_each                = local.subnet_cidrs.nat
  vpc_id                  = aws_vpc.cde.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-nat-${each.key}", Tier = "nat" }
}

resource "aws_subnet" "firewall" {
  for_each                = local.subnet_cidrs.firewall
  vpc_id                  = aws_vpc.cde.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-firewall-${each.key}", Tier = "firewall" }
}

resource "aws_subnet" "app" {
  for_each                = local.subnet_cidrs.app
  vpc_id                  = aws_vpc.cde.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-app-${each.key}", Tier = "app" }
}

resource "aws_subnet" "data" {
  for_each                = local.subnet_cidrs.data
  vpc_id                  = aws_vpc.cde.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-data-${each.key}", Tier = "data" }
}

resource "aws_internet_gateway" "cde" {
  vpc_id = aws_vpc.cde.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_eip" "nat" {
  for_each = local.azs
  domain   = "vpc"
  tags     = { Name = "${local.name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "cde" {
  for_each      = local.azs
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.nat[each.key].id

  tags       = { Name = "${local.name}-nat-${each.key}" }
  depends_on = [aws_internet_gateway.cde]
}
