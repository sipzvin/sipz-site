terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

# No profile or account id on purpose: this deploys into whatever account the caller's environment points at.
# Check `aws sts get-caller-identity` before every plan.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "sipz-site"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront only accepts certificates from us-east-1, whatever region everything else is in.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "sipz-site"
      ManagedBy = "terraform"
    }
  }
}
