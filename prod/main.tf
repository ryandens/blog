provider "aws" {
  region = var.region
}

module "my-static-site" {
  source   = "github.com/ryandens/terraform-aws-personal-modules//modules/static-site?ref=v0.0.3"
  dns_name = "ryandens.com"
}
