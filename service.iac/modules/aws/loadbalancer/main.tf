resource "aws_security_group" "lb" {
  for_each = { for k, v in var.service_apps : k => v }

  name        = "${each.key}-alb"
  description = "SecurityGroup that manages the ingress and egress connections from/to ${each.key} Application LoadBalancer"
  vpc_id      = var.aws_vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_elb" "app" {
  for_each        = { for k, v in var.service_apps : k => v }
  name            = "${replace(each.key, "_", "-")}-${replace(each.value.service, "_", "-")}"
  subnets         = var.service_settings[each.value.service].external ? var.aws_vpc_subnets_public.*.id : var.aws_vpc_subnets_private.*.id
  security_groups = [aws_security_group.lb[each.key].id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  # listener {
  #   instance_port      = 8000
  #   instance_protocol  = "http"
  #   lb_port            = 443
  #   lb_protocol        = "https"
  #   ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  # }

  # health_check {
  #   healthy_threshold   = 2
  #   unhealthy_threshold = 2
  #   timeout             = 3
  #   target              = "HTTP:8000/"
  #   interval            = 30
  # }


  tags = {
    dns_name    = var.service_apps_dns_zone[each.key].tags.dns_name
    dns_zone_id = var.service_apps_dns_zone[each.key].zone_id
  }

  depends_on = [aws_security_group.lb]
}


resource "aws_route53_record" "lb" {
  for_each = { for k, v in aws_elb.app : k => v }

  zone_id = var.service_apps_dns_zone[each.key].zone_id
  name    = var.service_apps_dns_zone[each.key].tags.dns_name
  type    = "A"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }
  depends_on = [aws_elb.app]
}

resource "tls_private_key" "app" {
  for_each = { for k, v in aws_elb.app : k => v }

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "app" {
  for_each = { for k, v in tls_private_key.app : k => v }

  key_algorithm   = tls_private_key.app[each.key].algorithm
  private_key_pem = tls_private_key.app[each.key].private_key_pem

  subject {
    common_name  = aws_elb.app[each.key].tags.dns_name
    organization = "EVRYTHNG Ltd."
  }

  validity_period_hours = 24
  is_ca_certificate     = false
  set_subject_key_id    = true

  dns_names = [
    aws_elb.app[each.key].tags.dns_name,
    "*.${aws_elb.app[each.key].tags.dns_name}"
  ]

  allowed_uses = [
    "server_auth",
    "key_encipherment",
    "digital_signature",
  ]
}

resource "aws_acm_certificate" "app" {
  for_each = { for k, v in tls_private_key.app : k => v }

  private_key      = tls_private_key.app[each.key].private_key_pem
  certificate_body = tls_self_signed_cert.app[each.key].cert_pem
}


resource "aws_acm_certificate" "lb_listener_https_default" {
  for_each = { for k, v in aws_elb.app : k => v }

  domain_name               = aws_elb.app[each.key].tags.dns_name
  subject_alternative_names = ["*.${aws_elb.app[each.key].tags.dns_name}"]

  validation_method = "DNS"

  tags = {
    dns_name    = var.service_apps_dns_zone[each.key].tags.dns_name
    dns_zone_id = var.service_apps_dns_zone[each.key].zone_id
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_elb.app]
}

resource "aws_route53_record" "lb_listener_https_default_cert_validation" {
  for_each = { for k, v in aws_acm_certificate.lb_listener_https_default : k => v }

  name    = aws_acm_certificate.lb_listener_https_default[each.key].domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.lb_listener_https_default[each.key].domain_validation_options.0.resource_record_type
  zone_id = aws_acm_certificate.lb_listener_https_default[each.key].tags.dns_zone_id
  records = [aws_acm_certificate.lb_listener_https_default[each.key].domain_validation_options.0.resource_record_value]
  ttl     = 60

  depends_on = [aws_acm_certificate.lb_listener_https_default]
}

# resource "aws_acm_certificate_validation" "lb_listener_https_default_cert" {
#   for_each = { for k, v in aws_acm_certificate.lb_listener_https_default : k => v }
#
#   certificate_arn = aws_acm_certificate.lb_listener_https_default[each.key].arn
#   validation_record_fqdns = [
#     aws_route53_record.lb_listener_https_default_cert_validation[each.key].fqdn,
#     # aws_route53_record.lb_listener_https_default_www_cert_validation[each.key].fqdn,
#     # aws_route53_record.lb_listener_https_default_wildcard_cert_validation[each.key].fqdn,
#   ]
#
#   depends_on = [
#     aws_acm_certificate.lb_listener_https_default,
#     aws_route53_record.lb_listener_https_default_cert_validation
#   ]
# }
