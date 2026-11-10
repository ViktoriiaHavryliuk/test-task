############################################################################
# security_groups.tf — stateful rules, chained by security group reference
#
# Three groups. No rule anywhere uses 0.0.0.0/0 as a source. The only
# 0.0.0.0/0 destination is app egress on 443, and the Network Firewall
# narrows that to the allow-listed domains.
#
# The aws_security_group resource removes the AWS default "allow all
# egress" rule on creation, so every egress rule below is deliberate.
############################################################################

# ---------------------------------------------------------------------------
# ALB: 443 from the finite client list in, app port to the app SG out
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB: HTTPS from allow-listed clients only (PCI 1.3.1)"
  vpc_id      = aws_vpc.cde.id
  tags        = { Name = "${local.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_clients" {
  for_each          = toset(var.allowed_client_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from allow-listed client ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to app targets"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port
}

# ---------------------------------------------------------------------------
# App: app port from the ALB SG in; 443 (firewall-filtered) and 3306 out
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "App instances: reachable only from the ALB (PCI 1.3.1), HTTPS egress only (PCI 1.3.2)"
  vpc_id      = aws_vpc.cde.id
  tags        = { Name = "${local.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS only; destination hosts enforced by Network Firewall"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "MySQL"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

# ---------------------------------------------------------------------------
# DB: 3306 from the app SG in; no egress rule at all (pre-baked AMI)
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "MySQL: 3306 from app only (PCI 1.3.1), no internet egress (PCI 1.3.2)"
  vpc_id      = aws_vpc.cde.id
  tags        = { Name = "${local.name}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from app instances only"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}
