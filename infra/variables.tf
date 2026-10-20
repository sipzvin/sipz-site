variable "region" {
  description = "Region for the site bucket. (The certificate is in us-east-1 regardless, because CloudFront accepts no other.)"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = var.region == "eu-west-1"

    error_message = "Everything for Sipz.vin is hosted in eu-west-1. Change this check deliberately if that ever needs to move."
  }
}

variable "domain" {
  description = "The apex domain the site is served on."
  type        = string
  default     = "sipz.vin"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain))
    error_message = "domain must be a bare domain name such as sipz.vin, with no scheme or path."
  }
}

variable "route53_zone_id" {
  description = "Id of the hosted zone for the domain. Created in sipz-foundation; take it from that stack's zone_id output."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]{8,}$", var.route53_zone_id))
    error_message = "route53_zone_id must look like Z0123456789ABCDEFGHIJ (the zone_id output of sipz-foundation)."
  }
}

variable "github_oidc_arn" {
  description = "ARN of the GitHub Actions OIDC provider. Created in sipz-foundation; take it from that stack's github_oidc_arn output. Null skips the deploy role."
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_arn))
    error_message = "github_oidc_arn must be the ARN of the token.actions.githubusercontent.com provider."
  }
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (US, Canada, Europe) is cheapest and fine for a handful of visitors."
  type        = string
  default     = "PriceClass_100"
}

variable "github_repo" {
  description = "owner/name of the repository allowed to deploy the site through GitHub Actions, using OIDC (no stored AWS keys). Null skips it."
  type        = string
  default     = null

  validation {
    condition     = var.github_repo == null || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must look like owner/name."
  }
}
