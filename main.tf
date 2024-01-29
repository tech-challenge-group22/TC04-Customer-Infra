/*====
Variables used across all modules
======*/
locals {
  production_availability_zones = ["us-east-1a", "us-east-1b"]
}

provider "aws" {
  region  = "${var.region}"
  profile = "lab"
}

terraform {
  backend "s3" {
    bucket         = "tc04-tfstate-customer"
    key            = "terraform.tfstate"
    region         = "us-east-1"
  }
}

module "networking" {
  source               = "./modules/networking"
  prefix          = "customer"
  vpc_cidr             = "10.0.0.0/16"
  public_subnets_cidr  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets_cidr = ["10.0.10.0/24", "10.0.20.0/24"]
  region               = "${var.region}"
  availability_zones   = "${local.production_availability_zones}"
  key_name             = "production_key"
}

module "rds" {
  source            = "./modules/rds"
  prefix       = "customer"
  allocated_storage = "10"
  database_name     = "${var.database_name}"
  database_username = "${var.database_username}"
  database_password = "${var.database_password}"
  subnet_ids        = module.networking.public_subnets_id
  vpc_id            = "${module.networking.vpc_id}"
  instance_class    = "db.t2.micro"
}

module "ecs" {
  source              = "./modules/ecs"
  prefix         = "customer"
  vpc_id              = "${module.networking.vpc_id}"
  availability_zones  = "${local.production_availability_zones}"
  repository_name     = "customer/production"
  subnets_ids         = module.networking.private_subnets_id
  public_subnet_ids   = module.networking.public_subnets_id
  security_groups_ids = [
    module.networking.security_groups_ids,
    module.rds.db_access_sg_id
  ]
  database_endpoint   = "${module.rds.rds_address}"
  database_name       = "${var.database_name}"
  database_username   = "${var.database_username}"
  database_password   = "${var.database_password}"
  dbhost              = "${module.rds.rds_address}"
  execution_arn_role  = "${var.lab_role_arn}"
  rds_id              = "${module.rds.rds_id}"
}
