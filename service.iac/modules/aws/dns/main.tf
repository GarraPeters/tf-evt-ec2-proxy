locals {
  service_name = length(keys(var.service_settings)) > 0 ? element(keys(var.service_settings), 0) : ""
}

resource "aws_route53_zone" "srv" {
  for_each = { for k, v in var.service_settings : k => v }

  name          = "${replace(each.key, "_", "-")}.${replace(var.evt_env_domain, "_", "-")}"
  force_destroy = true

  tags = {
    dns_name = "${replace(each.key, "_", "-")}.${replace(var.evt_env_domain, "_", "-")}"
  }
}

resource "aws_route53_record" "srv_ns" {
  for_each = { for zone in aws_route53_zone.srv : zone.tags.dns_name => zone }

  allow_overwrite = true

  zone_id = var.evt_env_domain_zone_id
  name    = each.value.name
  type    = "NS"
  ttl     = 86400

  records = [
    each.value.name_servers.0,
    each.value.name_servers.1,
    each.value.name_servers.2,
    each.value.name_servers.3,
  ]

  depends_on = [aws_route53_zone.srv]
}

resource "aws_route53_zone" "app" {
  for_each = { for k, v in var.service_apps : k => v }

  name          = "${replace(each.key, "_", "-")}.${replace(aws_route53_zone.srv[local.service_name].tags.dns_name, "_", "-")}"
  force_destroy = true

  tags = {
    dns_name = "${replace(each.key, "_", "-")}.${replace(aws_route53_zone.srv[local.service_name].tags.dns_name, "_", "-")}"
  }

  depends_on = [aws_route53_zone.srv]
}

resource "aws_route53_record" "app_ns" {
  for_each = { for zone in aws_route53_zone.app : zone.tags.dns_name => zone }

  allow_overwrite = true

  zone_id = aws_route53_zone.srv[local.service_name].zone_id
  name    = each.key
  type    = "NS"
  ttl     = 86400

  records = [
    each.value.name_servers.0,
    each.value.name_servers.1,
    each.value.name_servers.2,
    each.value.name_servers.3,
  ]

  depends_on = [aws_route53_zone.app]
}
