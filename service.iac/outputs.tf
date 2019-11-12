output "service_dns_zone" {
  value = module.dns.service_dns_zone
}

output "service_dns_record_ns" {
  value = module.dns.service_dns_record_ns
}

output "service_apps_dns_zone" {
  value = module.dns.service_apps_dns_zone
}

output "service_apps_dns_record_ns" {
  value = module.dns.service_apps_dns_record_ns
}
