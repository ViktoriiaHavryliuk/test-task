############################################################################
# alb.tf — internet-facing ALB with an HTTPS listener only
#
# There is deliberately no port 80 listener and no HTTP-to-HTTPS redirect:
# the current environment's "80 from 0.0.0.0/0" is the finding, and a
# redirect would still require an open port 80.
############################################################################

resource "aws_lb" "cde" {
  name                       = "${local.name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = [for az in var.availability_zones : aws_subnet.alb[az].id]
  drop_invalid_header_fields = true

  tags = { Name = "${local.name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name}-app"
  port        = local.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.cde.id
  target_type = "instance"

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name}-app" }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.cde.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
