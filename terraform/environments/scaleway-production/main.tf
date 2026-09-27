terraform {
  required_version = ">= 1.5.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40.0"
    }
  }
}

provider "scaleway" {
  organization_id = var.scaleway_organization_id
  project_id      = var.scaleway_project_id
  region          = var.scaleway_region
  zone            = var.scaleway_zone
}

module "network" {
  source               = "../../modules/scaleway/network"
  project_id           = var.scaleway_project_id
  vpc_name             = "eu1-paris-vpc"
  private_network_name = "eu1-paris-pn"
  lb_name              = "eu1-paris-lb"
  zone                 = var.scaleway_zone
  tags                 = ["env=production", "cluster=eu1.paris.qtrn.io", "org=quatrain-technologies", "arch=arm64"]
}

module "kapsule" {
  source             = "../../modules/scaleway/kapsule-cluster"
  project_id         = var.scaleway_project_id
  cluster_name       = "eu1.paris.qtrn.io"
  k8s_version        = "1.34.6"
  region             = var.scaleway_region
  private_network_id = module.network.private_network_id
  node_type          = "STANDARD2-A2C-8G" # Scaleway Ampere Altra ARM64 (2 vCPU, 8 GiB RAM)
  min_nodes          = 3
  max_nodes          = 8
  tags               = ["env=production", "cluster=eu1.paris.qtrn.io", "org=quatrain-technologies", "arch=arm64"]
}

module "dns" {
  source         = "../../modules/scaleway/dns"
  enabled        = var.enable_scaleway_dns
  enable_aaaa    = false # Keep IPv4 only during Let's Encrypt validation
  project_id     = var.scaleway_project_id
  dns_zone       = var.dns_zone
  lb_public_ip   = module.network.public_ip
  lb_public_ipv6 = module.network.public_ipv6
  subdomains     = ["@", "*", "eu1.paris", "*.eu1.paris", "argocd.eu1.paris", "eu1.lorawan", "*.m2m", "eu1.lorawan.m2m", "git"]
}
