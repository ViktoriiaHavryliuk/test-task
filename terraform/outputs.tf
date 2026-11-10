output "alb_dns_name" {
  description = "Public DNS name of the ALB. Reachable on 443 from allowed_client_cidrs only."
  value       = aws_lb.cde.dns_name
}

output "app_asg_name" {
  description = "ASG of the app instance; use aws ec2 get-console-output on its instance for the boot log."
  value       = aws_autoscaling_group.app.name
}

output "db_private_ip" {
  description = "Private IP of the MySQL instance (data tier)."
  value       = aws_instance.db.private_ip
}

output "subnet_cidrs" {
  description = "Subnet CIDR per tier and AZ."
  value       = local.subnet_cidrs
}

output "log_groups" {
  description = "Where the audit evidence lands."
  value = {
    firewall_alert = aws_cloudwatch_log_group.firewall_alert.name
    firewall_flow  = aws_cloudwatch_log_group.firewall_flow.name
  }
}
