resource "aws_lb_target_group" "eks" {
  name = "eks-nodes"
  port = 30000
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id
  target_type = "instance"

  health_check {
    path                = "/ping"
    port                = 30001
    timeout             = 5
    interval            = 30
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_security_group" "eks-alb" {
  name        = "eks-alb-public"
  description = "Security group allowing public traffic for the eks load balancer."
  vpc_id      = aws_vpc.vpc.id
 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
        "Name" = "eks-alb-${var.cluster_name}"
        "Environment" = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
}
 
resource "aws_security_group_rule" "eks-alb-public-https" {
  description       = "Allow eks load balancer to communicate with public traffic securely."
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks-alb.id
  to_port           = 443
  type              = "ingress"
}
 
resource "aws_security_group_rule" "eks-alb-public-http" {
  description       = "Allow eks load balancer to communicate with public traffic."
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.eks-alb.id
  to_port           = 80
  type              = "ingress"
}

resource "aws_security_group_rule" "eks-alb-internal-https" {
  description       = "Allow eks load balancer to communicate with internal traffic securely."
  cidr_blocks       = var.whitelisted_hosts
  from_port         = 8443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks-alb.id
  to_port           = 8443
  type              = "ingress"
}

data "local_file" "private_key" {
  filename = "certs/${var.public_domain}.key"
}

data "local_file" "public_key" {
  filename = "certs/${var.public_domain}.crt"
}

#data "local_file" "ca_bundle" {
#  filename = "certs/${var.public_domain}.ca-bundle"
#}

resource "aws_acm_certificate" "cert" {
  private_key = data.local_file.private_key.content
  certificate_body = data.local_file.public_key.content
  #certificate_chain = data.local_file.ca_bundle.content
}

resource "aws_alb" "eks-alb" {
  name            = "eks-alb"
  subnets         = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.eks-node.id, aws_security_group.eks-alb.id]
  ip_address_type = "ipv4"
  
  tags = {
        "Name" = "eks-alb-${var.cluster_name}"
        "Environment" = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
}

resource "aws_alb_listener" "eks-alb" {
  load_balancer_arn = aws_alb.eks-alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type              = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
 
resource "aws_alb_listener" "eks-alb-ssl" {
  load_balancer_arn = aws_alb.eks-alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-FS-1-2-Res-2019-08"
  certificate_arn   = aws_acm_certificate.cert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks.arn
  }
}

resource "aws_alb_listener_rule" "eks-alb-ssl-redirect-monitoring" {
  listener_arn = aws_alb_listener.eks-alb-ssl.arn
  
  action {
    type = "redirect"

    redirect {
      port        = "8443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    path_pattern {
      values = ["/monitoring/*"]
    }
  }

  condition {
    host_header {
      values = [var.public_domain, aws_alb.eks-alb.dns_name]
    }
  }
}

resource "aws_alb_listener" "eks-alb-internal-ssl" {
  load_balancer_arn = aws_alb.eks-alb.arn
  port              = 8443
  protocol          = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-FS-1-2-Res-2019-08"
  certificate_arn   = aws_acm_certificate.cert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks.arn
  }
}
