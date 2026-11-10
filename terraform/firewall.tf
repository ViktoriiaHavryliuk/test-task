############################################################################
# firewall.tf — AWS Network Firewall for CDE egress (PCI DSS 1.3.2)
#
# Allows HTTPS from the app subnets to the domains in
# local.allowed_egress_domains and drops everything else. Sits in the
# dedicated firewall subnets; routing.tf sends app egress through it.
#
# Expects: aws_vpc.cde, aws_subnet.firewall[az], local.allowed_egress_domains
############################################################################

# ---------------------------------------------------------------------------
# 1. Rule group: the domain allow-list
# ---------------------------------------------------------------------------
# A "domain list" stateful rule group. AWS generates Suricata pass rules
# that match the TLS SNI (and HTTP Host header) against the list. Only
# traffic whose source is in HOME_NET is evaluated, so HOME_NET is pinned
# to the VPC CIDR.
resource "aws_networkfirewall_rule_group" "egress_domains" {
  name        = "cde-egress-allowlist"
  description = "Domains the CDE app may reach over HTTPS"
  type        = "STATEFUL"
  capacity    = 100

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [aws_vpc.cde.cidr_block]
        }
      }
    }

    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = local.allowed_egress_domains
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "cde-egress-allowlist" }
}

# ---------------------------------------------------------------------------
# 2. Firewall policy: strict order, default drop
# ---------------------------------------------------------------------------
# Stateless layer forwards everything to the stateful engine.
# Stateful layer evaluates the allow-list first (priority 10); anything
# that reaches the default action is dropped.
#
# Why drop_established and not drop_strict: the SNI is only visible after
# the TCP handshake. drop_established lets the three handshake packets
# through so the hostname can be read, then drops the connection as soon
# as data flows if no pass rule matched. No application data ever leaves
# for a non-listed host. drop_strict would drop the SYN and the allow-list
# could never match.
resource "aws_networkfirewall_firewall_policy" "cde" {
  name        = "cde-egress-policy"
  description = "Allow-listed HTTPS egress only; everything else dropped"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_default_actions = ["aws:drop_established", "aws:alert_established"]

    stateful_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.egress_domains.arn
    }
  }

  tags = { Name = "cde-egress-policy" }
}

# ---------------------------------------------------------------------------
# 3. The firewall: one endpoint per firewall subnet (one per AZ)
# ---------------------------------------------------------------------------
resource "aws_networkfirewall_firewall" "cde" {
  name                = "cde-egress"
  description         = "CDE egress inspection"
  vpc_id              = aws_vpc.cde.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.cde.arn

  # POC values. Set both to true before production so a stray apply or
  # console click cannot remove the control.
  delete_protection        = false
  subnet_change_protection = false

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  tags = { Name = "cde-egress" }
}

# ---------------------------------------------------------------------------
# 4. Logging: alerts (matches and drops) and flows (every connection)
# ---------------------------------------------------------------------------
# PCI DSS 10.5.1 wants 12 months of audit log history with 3 months
# immediately available, hence 400 days retention.
resource "aws_cloudwatch_log_group" "firewall_alert" {
  name              = "/cde/network-firewall/alert"
  retention_in_days = 400
  tags              = { Name = "cde-firewall-alert" }
}

resource "aws_cloudwatch_log_group" "firewall_flow" {
  name              = "/cde/network-firewall/flow"
  retention_in_days = 400
  tags              = { Name = "cde-firewall-flow" }
}

resource "aws_networkfirewall_logging_configuration" "cde" {
  firewall_arn = aws_networkfirewall_firewall.cde.arn

  logging_configuration {
    log_destination_config {
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_alert.name
      }
    }

    log_destination_config {
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_flow.name
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Outputs used in discussion and by routing.tf
# ---------------------------------------------------------------------------
output "firewall_endpoint_ids" {
  description = "Network Firewall endpoint id per AZ"
  value = {
    for state in aws_networkfirewall_firewall.cde.firewall_status[0].sync_states :
    state.availability_zone => state.attachment[0].endpoint_id
  }
}
