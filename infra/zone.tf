# The hosted zone is created here, not in the API stack, so tearing the API down can never take the website's DNS with it.
# The API stack takes the zone id as an input (route53_zone_id) and adds only its own record.
resource "aws_route53_zone" "main" {
  count   = var.create_zone ? 1 : 0
  name    = var.domain
  comment = "sipz.wine: site and API"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  zone_id = var.create_zone ? aws_route53_zone.main[0].zone_id : var.existing_zone_id
}

check "zone_given" {
  assert {
    condition     = var.create_zone || var.existing_zone_id != null
    error_message = "Set existing_zone_id when create_zone is false."
  }
}
