############################################################################
# nacl.tf — network ACLs for the CDE proof of concept (diagram 2)
#
# One ACL per subnet tier, each with the minimum stateless rule set for the
# paths in routing.tf and an explicit deny-all as the last rule in both
# directions. The explicit deny is what PCI DSS 1.3.1 / 1.3.2 ask to see.
#
# NACLs are stateless, so every allowed flow needs two rules: the request
# port in one direction and the ephemeral reply ports (1024-65535) in the
# other. Replies from the internet arrive with the remote host as source,
# so those rules use 0.0.0.0/0 on ephemeral ports; the port restriction and
# the domain allow-list in the firewall are what keep that narrow.
#
# Not subject to NACLs (no rules needed): Route 53 Resolver at VPC+2,
# instance metadata, Time Sync.
#
# Expects, from the other files:
#   aws_vpc.cde, aws_subnet.{alb,nat,firewall,app,data}[az]
#   var.availability_zones, var.allowed_client_cidrs, local.app_port
############################################################################

locals {
  any_v4   = "0.0.0.0/0"
  eph_from = 1024
  eph_to   = 65535

  tier_cidrs = {
    alb      = [for az in var.availability_zones : aws_subnet.alb[az].cidr_block]
    nat      = [for az in var.availability_zones : aws_subnet.nat[az].cidr_block]
    firewall = [for az in var.availability_zones : aws_subnet.firewall[az].cidr_block]
    app      = [for az in var.availability_zones : aws_subnet.app[az].cidr_block]
    data     = [for az in var.availability_zones : aws_subnet.data[az].cidr_block]
  }

  tier_subnet_ids = {
    alb      = { for az in var.availability_zones : az => aws_subnet.alb[az].id }
    nat      = { for az in var.availability_zones : az => aws_subnet.nat[az].id }
    firewall = { for az in var.availability_zones : az => aws_subnet.firewall[az].id }
    app      = { for az in var.availability_zones : az => aws_subnet.app[az].id }
    data     = { for az in var.availability_zones : az => aws_subnet.data[az].id }
  }

  # Rule numbers: 1xx client list, 2xx/3xx/4xx one block per peer tier.
  # Index i is the position in the CIDR list, so numbers stay unique.
  nacl_rules = {

    # -------- ALB subnets (public) --------
    alb = concat(
      # in: HTTPS from the finite client list only
      [for i, c in var.allowed_client_cidrs : { num = 100 + i, egress = false, cidr = c, from = 443, to = 443 }],
      # in: replies from app targets to the ALB's ephemeral ports
      [for i, c in local.tier_cidrs.app : { num = 200 + i, egress = false, cidr = c, from = local.eph_from, to = local.eph_to }],
      # out: replies to the clients
      [for i, c in var.allowed_client_cidrs : { num = 100 + i, egress = true, cidr = c, from = local.eph_from, to = local.eph_to }],
      # out: forwarded requests and health checks to the app port
      [for i, c in local.tier_cidrs.app : { num = 200 + i, egress = true, cidr = c, from = local.app_port, to = local.app_port }],
    )

    # -------- NAT subnets (public) --------
    nat = concat(
      # in: replies from the internet to the NAT gateway
      [{ num = 100, egress = false, cidr = local.any_v4, from = local.eph_from, to = local.eph_to }],
      # in: HTTPS from the app subnets (already passed the firewall)
      [for i, c in local.tier_cidrs.app : { num = 200 + i, egress = false, cidr = c, from = 443, to = 443 }],
      # out: HTTPS to the internet; the firewall decides which hosts
      [{ num = 100, egress = true, cidr = local.any_v4, from = 443, to = 443 }],
      # out: replies back towards the app subnets (via the firewall route)
      [for i, c in local.tier_cidrs.app : { num = 200 + i, egress = true, cidr = c, from = local.eph_from, to = local.eph_to }],
    )

    # -------- Firewall subnets --------
    firewall = concat(
      # in: HTTPS from the app subnets on the way out
      [for i, c in local.tier_cidrs.app : { num = 100 + i, egress = false, cidr = c, from = 443, to = 443 }],
      # in: replies from the internet on the way back (source is the remote host)
      [{ num = 200, egress = false, cidr = local.any_v4, from = local.eph_from, to = local.eph_to }],
      # out: HTTPS onward to the NAT gateway / internet
      [{ num = 100, egress = true, cidr = local.any_v4, from = 443, to = 443 }],
      # out: replies to the app subnets
      [for i, c in local.tier_cidrs.app : { num = 200 + i, egress = true, cidr = c, from = local.eph_from, to = local.eph_to }],
    )

    # -------- App subnets (private) --------
    app = concat(
      # in: app port from the ALB subnets only
      [for i, c in local.tier_cidrs.alb : { num = 100 + i, egress = false, cidr = c, from = local.app_port, to = local.app_port }],
      # in: MySQL replies
      [for i, c in local.tier_cidrs.data : { num = 200 + i, egress = false, cidr = c, from = local.eph_from, to = local.eph_to }],
      # in: replies from secureweb.com / example.com via the firewall
      [{ num = 400, egress = false, cidr = local.any_v4, from = local.eph_from, to = local.eph_to }],
      # out: replies to the ALB
      [for i, c in local.tier_cidrs.alb : { num = 100 + i, egress = true, cidr = c, from = local.eph_from, to = local.eph_to }],
      # out: MySQL
      [for i, c in local.tier_cidrs.data : { num = 200 + i, egress = true, cidr = c, from = 3306, to = 3306 }],
      # out: HTTPS only; destination hosts are enforced by the firewall
      [{ num = 400, egress = true, cidr = local.any_v4, from = 443, to = 443 }],
    )

    # -------- Data subnets (private) --------
    data = concat(
      # in: MySQL from the app subnets only
      [for i, c in local.tier_cidrs.app : { num = 100 + i, egress = false, cidr = c, from = 3306, to = 3306 }],
      # out: MySQL replies
      [for i, c in local.tier_cidrs.app : { num = 100 + i, egress = true, cidr = c, from = local.eph_from, to = local.eph_to }],
    )
  }

  nacl_rule_map = merge([
    for tier, rules in local.nacl_rules : {
      for r in rules :
      "${tier}-${r.egress ? "out" : "in"}-${r.num}" => merge(r, { tier = tier })
    }
  ]...)

  nacl_deny_map = {
    for pair in setproduct(keys(local.nacl_rules), ["in", "out"]) :
    "${pair[0]}-${pair[1]}" => { tier = pair[0], egress = pair[1] == "out" }
  }

  nacl_assoc_map = merge([
    for tier in keys(local.nacl_rules) : {
      for az in var.availability_zones :
      "${tier}-${az}" => { tier = tier, az = az }
    }
  ]...)
}

resource "aws_network_acl" "tier" {
  for_each = local.nacl_rules
  vpc_id   = aws_vpc.cde.id

  tags = {
    Name = "cde-${each.key}"
    Tier = each.key
  }
}

resource "aws_network_acl_rule" "allow" {
  for_each = local.nacl_rule_map

  network_acl_id = aws_network_acl.tier[each.value.tier].id
  rule_number    = each.value.num
  egress         = each.value.egress
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = each.value.from
  to_port        = each.value.to
}

# Explicit deny-all, last rule in each direction on every tier. AWS already
# has an implicit "*" deny, but the requirement asks for a specific deny
# statement an auditor can point at.
resource "aws_network_acl_rule" "deny_all" {
  for_each = local.nacl_deny_map

  network_acl_id = aws_network_acl.tier[each.value.tier].id
  rule_number    = 32000
  egress         = each.value.egress
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = local.any_v4
}

resource "aws_network_acl_association" "tier" {
  for_each = local.nacl_assoc_map

  network_acl_id = aws_network_acl.tier[each.value.tier].id
  subnet_id      = local.tier_subnet_ids[each.value.tier][each.value.az]
}
