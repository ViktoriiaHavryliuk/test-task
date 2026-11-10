############################################################################
# compute_app.tf — app instance in an Auto Scaling Group (desired 1)
#
# Launch template + ASG mirrors the existing setup. Set min/max/desired to
# 1 and it behaves like a single instance that self-heals.
############################################################################

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-app-"
  image_id      = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type = local.app_instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/app-user-data.sh", {
    app_port    = local.app_port
    package_url = var.app_package_url
    db_host     = aws_instance.db.private_ip
    db_password = random_password.db_app.result
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-app", Tier = "app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-app"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = [for az in var.availability_zones : aws_subnet.app[az].id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }

  # Egress at boot (package from example.com) only works once the firewall
  # and routes exist.
  depends_on = [
    aws_networkfirewall_firewall.cde,
    aws_route.app_default,
  ]
}
