module "dns" {
  source = "./modules/aws/dns"

  aws_vpc_id              = var.aws_vpc_id
  aws_vpc_subnets_public  = var.aws_vpc_subnets_public
  aws_vpc_subnets_private = var.aws_vpc_subnets_private

  evt_env_domain         = var.evt_env_domain
  evt_env_domain_zone_id = var.evt_env_domain_zone_id

  service_settings = var.service_settings
  service_apps     = var.service_apps

}

module "loadbalancer" {
  source = "./modules/aws/loadbalancer"

  service_settings = var.service_settings
  service_apps     = var.service_apps

  aws_vpc_id              = var.aws_vpc_id
  aws_vpc_subnets_public  = var.aws_vpc_subnets_public
  aws_vpc_subnets_private = var.aws_vpc_subnets_private

  service_dns_zone      = module.dns.service_dns_zone
  service_apps_dns_zone = module.dns.service_apps_dns_zone
}



module "ecs" {
  source = "./modules/aws/ecs"

  service_settings = var.service_settings
  service_apps     = var.service_apps

  aws_vpc_id              = var.aws_vpc_id
  aws_vpc_subnets_public  = var.aws_vpc_subnets_public
  aws_vpc_subnets_private = var.aws_vpc_subnets_private

  service_apps_lb = module.loadbalancer.service_apps_elb
  # service_apps_lb_listener_http  = module.loadbalancer.service_apps_lb_listener_http
  # service_apps_lb_listener_https = module.loadbalancer.service_apps_lb_listener_https

  # service_db = module.database.service_db

}

