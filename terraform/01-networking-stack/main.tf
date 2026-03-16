terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "bia-eks-s3-remote-backend-bucket"
    key          = "networking-stack/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    # dynamodb_table = "bia-eks-s3-state-locking-table"
  }
}

provider "aws" {
  region = var.auth.region

  assume_role {
    role_arn = var.auth.assume_role_arn
  }

  default_tags {
    tags = var.tags
  }
}