############################################################################
# routing.tf — route tables for the CDE POC
#
# Expects these resources, defined in the other files of this module:
#   aws_vpc.cde
#   aws_internet_gateway.cde
#   aws_subnet.alb[az]        public  — Application Load Balancer only
#   aws_subnet.nat[az]        public  — NAT gateway only
#   aws_subnet.firewall[az]   private — AWS Network Firewall endpoint
#   aws_subnet.app[az]        private — app EC2 / ASG
#   aws_subnet.data[az]       private — MySQL EC2
#   aws_nat_gateway.cde[az]   one per AZ, placed in aws_subnet.nat[az]
#   aws_networkfirewall_firewall.cde   one endpoint per firewall subnet
#   var.availability_zones    e.g. ["eu-central-1a", "eu-central-1b"]
#
# Traffic paths
#   inbound   internet -> IGW -> alb subnet -> app subnet              (local route, both ways)
#   outbound  app subnet -> firewall endpoint -> NAT gateway -> IGW -> internet
#   return    IGW -> NAT gateway -> firewall endpoint -> app subnet    (symmetric, same AZ)
#   app <-> data   local route only; data subnets have no 0.0.0.0/0 route at all
#
# Why ALB and NAT get separate subnets
#   The NAT subnet must route "app CIDR -> firewall endpoint" so replies are
#   inspected. If the ALB shared that subnet, ALB -> app traffic would also be
#   pushed through the firewall while app -> ALB replies took the local route:
#   an asymmetric flow the stateful engine would drop. Separate subnets keep
#   the firewall on the egress path only.
#
# Why tables are per AZ
#   Firewall endpoints and NAT gateways are zonal. A flow that leaves through
#   the AZ-a firewall endpoint must return through it, so each AZ gets its own
#   app, firewall and NAT route tables. Only the data tier shares one table,
#   because it never leaves the VPC.
############################################################################

locals {
  azs = toset(var.availability_zones)

  # AZ name -> Network Firewall endpoint id in that AZ
  firewall_endpoint_id = {
    for state in aws_networkfirewall_firewall.cde.firewall_status[0].sync_states :
    state.availability_zone => state.attachment[0].endpoint_id
  }
}

# ---------------------------------------------------------------------------
# ALB subnets (public): default route to the IGW, nothing else
# ---------------------------------------------------------------------------
resource "aws_route_table" "alb" {
  for_each = local.azs
  vpc_id   = aws_vpc.cde.id

  tags = {
    Name = "cde-alb-${each.key}"
    Tier = "alb"
  }
}

resource "aws_route" "alb_default" {
  for_each               = local.azs
  route_table_id         = aws_route_table.alb[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.cde.id
}

resource "aws_route_table_association" "alb" {
  for_each       = local.azs
  subnet_id      = aws_subnet.alb[each.key].id
  route_table_id = aws_route_table.alb[each.key].id
}

# ---------------------------------------------------------------------------
# NAT subnets (public): IGW for the internet, firewall endpoint for the way back
# ---------------------------------------------------------------------------
resource "aws_route_table" "nat" {
  for_each = local.azs
  vpc_id   = aws_vpc.cde.id

  tags = {
    Name = "cde-nat-${each.key}"
    Tier = "nat"
  }
}

resource "aws_route" "nat_default" {
  for_each               = local.azs
  route_table_id         = aws_route_table.nat[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.cde.id
}

# More specific than the VPC local route, so replies from the NAT gateway to
# the app subnet go back through the firewall endpoint of the same AZ.
resource "aws_route" "nat_to_app_via_firewall" {
  for_each               = local.azs
  route_table_id         = aws_route_table.nat[each.key].id
  destination_cidr_block = aws_subnet.app[each.key].cidr_block
  vpc_endpoint_id        = local.firewall_endpoint_id[each.key]
}

resource "aws_route_table_association" "nat" {
  for_each       = local.azs
  subnet_id      = aws_subnet.nat[each.key].id
  route_table_id = aws_route_table.nat[each.key].id
}

# ---------------------------------------------------------------------------
# Firewall subnets: whatever the firewall passes goes to the NAT gateway
# ---------------------------------------------------------------------------
resource "aws_route_table" "firewall" {
  for_each = local.azs
  vpc_id   = aws_vpc.cde.id

  tags = {
    Name = "cde-firewall-${each.key}"
    Tier = "firewall"
  }
}

resource "aws_route" "firewall_default" {
  for_each               = local.azs
  route_table_id         = aws_route_table.firewall[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.cde[each.key].id
}

resource "aws_route_table_association" "firewall" {
  for_each       = local.azs
  subnet_id      = aws_subnet.firewall[each.key].id
  route_table_id = aws_route_table.firewall[each.key].id
}

# ---------------------------------------------------------------------------
# App subnets (private): the only way out is the firewall endpoint
# ---------------------------------------------------------------------------
resource "aws_route_table" "app" {
  for_each = local.azs
  vpc_id   = aws_vpc.cde.id

  tags = {
    Name = "cde-app-${each.key}"
    Tier = "app"
  }
}

resource "aws_route" "app_default" {
  for_each               = local.azs
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_id[each.key]
}

resource "aws_route_table_association" "app" {
  for_each       = local.azs
  subnet_id      = aws_subnet.app[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}

# ---------------------------------------------------------------------------
# Data subnets (private): local route only
# ---------------------------------------------------------------------------
# No 0.0.0.0/0 route, no NAT, no firewall, no endpoints. MySQL reaches the
# app subnets through the implicit local route and nothing else. The AMI is
# pre-baked, so nothing is downloaded at boot. One table serves both AZs
# because nothing here is zonal.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.cde.id

  tags = {
    Name = "cde-data"
    Tier = "data"
  }
}

resource "aws_route_table_association" "data" {
  for_each       = local.azs
  subnet_id      = aws_subnet.data[each.key].id
  route_table_id = aws_route_table.data.id
}
