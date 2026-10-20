variable "region" {
  description = "Region for the site bucket."
  type        = string
  default     = "eu-west-2"
}

variable "domain" {
  description = "The apex domain the site is served on."
  type        = string
  default     = "sipz.wine"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain))
    error_message = "domain must be a bare domain name such as sipz.wine, with no scheme or path."
  }
}

variable "create_zone" {
  description = "Create the Route 53 hosted zone. Set false if the zone already exists and pass its id as existing_zone_id."
  type        = bool
  default     = true
}

variable "existing_zone_id" {
  description = "Id of an existing hosted zone for the domain. Only used when create_zone is false."
  type        = string
  default     = null
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
