resource "aws_lb" "api" {
  name               = local.name
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.alb.id]

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb/access"
    enabled = true
  }

  connection_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb/connection"
    enabled = true
  }

  depends_on = [
    aws_s3_bucket_policy.alb_logs,
    aws_s3_bucket_server_side_encryption_configuration.alb_logs,
    aws_s3_bucket_lifecycle_configuration.alb_logs,
  ]

  tags = {
    Name = "${local.name}-internal"
  }
}

resource "aws_lb_target_group" "api" {
  name        = local.name
  target_type = "lambda"

  health_check {
    enabled             = true
    interval            = 35
    path                = "/health"
    timeout             = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "${local.name}-lambda"
  }
}

resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_lambda_function.api.arn
  depends_on       = [aws_lambda_permission.alb]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.server.arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  mutual_authentication {
    mode            = "verify"
    trust_store_arn = aws_lb_trust_store.client_ca.arn
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
