output "service_dns_zone" {
  value = aws_route53_zone.srv
}

output "service_dns_record_ns" {
  value = aws_route53_record.srv_ns
}

output "service_apps_dns_zone" {
  value = aws_route53_zone.app
}

output "service_apps_dns_record_ns" {
  value = aws_route53_record.app_ns
}
