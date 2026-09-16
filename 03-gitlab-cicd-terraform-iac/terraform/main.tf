# Root module - orchestrates all sub-modules

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr        = var.vpc_cidr
  environment     = var.environment
  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
}

module "iam" {
  source = "./modules/iam"

  environment = var.environment
}

module "compute" {
  source = "./modules/compute"

  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  private_subnets      = module.vpc.private_subnet_ids
  instance_type        = var.instance_type
  key_name             = var.key_name
  instance_profile_name = module.iam.instance_profile_name
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
}
