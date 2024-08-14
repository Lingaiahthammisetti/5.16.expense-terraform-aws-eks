

resource "aws_lb" "ingress_alb" {
    name = "${var.project_name}-${var.environment}-ingress-alb"
    internal =  false #public ALB
    load_balancer_type = "application"
    security_groups  = [data.aws_ssm_parameter.ingress_alb_sg_id.value]

    subnets = split(",", data.aws_ssm_parameter.ingress_alb_sg_id.value)
    enable_deletion_protection = false

    tags = merge(
        var.common_tags,
        {
            Name = "${var.project_name}-${var.environment}-ingress-alb"
        }
    )
}
resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.app_alb.arn
    port              = "80"
    protocol          = "HTTP"
    default_action {
        type = "fixed-response"
        fixed_response {
            content_type = "text/html"
            message_body = "<h1>This is fixed response from WEB ALB</h1>"
            status_code  = "200"
        }
    }
}
resource "aws_lb_listener" "https" {
    load_balancer_arn = aws_lb.ingress_alb.arn
    port              = "443"
    protocol          = "HTTPS"
    certificate_arn   = data.aws_ssm_parameter.acm_certificate_arn.value
    ssl_policy        = "ELBSecurityPolicy-2016-08"

    default_action {
        type = "fixed-response"
        fixed_response {
            content_type = "text/html"
            message_body = "<h1>This is fixed response from WEB ALB</h1>"
            status_code  = "200"
        }
    }
}

resource "aws_lb_target_group" "frontend" {
    name = "${var.project_name}-${var.environment}-frontend"
    port              = 8080
    protocol          = "HTTP"
    target_type       = "ip"

    vpc_id            =data.aws_ssm_parameter.vpc_id.value

    health_check {
        path        = "/"
        port        = 8080
        protocol    = "HTTP"
        health_threshold  = 2
        unhealth_threshold  = 2
        matcher             = "200"

        }
    }
}

resource "aws_lb_listener_rule" "frontend" {
    listener_arn = aws_lb_listener.https.arn
    priority     = 100 # less number will be first validated

    action {
        type  ="forward"
        target_group_arn = aws_lb_target_group.frontend.arn
    }
    condition {
        host_header {
            # expense-dev.daws78s.online ---> frontend pod
            values = ["expense=${var.environment}.${var.zone_id}"]
        }
    }
}
module "records" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "~> 2.0"
  zone_name = var.zone_name

    records = [
        {
            name = "expense-${var.environment}"
            type = "A"
            ttl = 1
            allow_overwrite = true
            records = {
                name = aws_lb.ingress_alb.dns_name
                zone_id = aws_lb.ingress_alb.zone_id
           }
        }
    ]
}

