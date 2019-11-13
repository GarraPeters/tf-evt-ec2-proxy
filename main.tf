module "service" {
  source = "./service.iac"

  evt_env_domain         = var.evt_env_domain
  evt_env_domain_zone_id = var.evt_env_domain_zone_id

  aws_vpc_id              = var.aws_vpc_id
  aws_vpc_subnets_public  = var.aws_vpc_subnets_public
  aws_vpc_subnets_private = var.aws_vpc_subnets_private

  proxy_dest = "https://api.evrythng.com"

  service_settings = {
    "evt_srv_001" = {
      external = true
    }
  }

  service_apps = {
    "app_123" = {
      service = "evt_srv_001"
      image   = "nginx:latest",
      port    = "80"
    }
  }

}
