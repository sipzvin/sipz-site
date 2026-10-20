# The hosted zone is NOT created here. It lives in sipz-foundation so that deleting the site can never delete the DNS the API also uses.
# This stack only adds its own records into it, by id.
locals {
  zone_id = var.route53_zone_id
}
